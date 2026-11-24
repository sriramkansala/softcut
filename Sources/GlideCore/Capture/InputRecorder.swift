import AppKit
import ApplicationServices
import UniformTypeIdentifiers

/// Records the mouse while a recording runs: position (polled at 120 Hz so motion is
/// smooth), clicks, scrolls and cursor-shape changes. Cursor images are saved as PNGs so
/// the renderer can draw the cursor itself.
///
/// Optionally it also records when keys are pressed and where the text caret is, so the
/// editor can zoom in while someone types. Which keys were pressed is never recorded.
public final class InputRecorder: @unchecked Sendable {
    public struct Options: Sendable {
        /// Record the time of each key press. Needs Input Monitoring permission.
        public var captureKeys = false
        /// Record the caret position while typing. Needs Accessibility permission.
        public var trackFocus = false

        public init(captureKeys: Bool = false, trackFocus: Bool = false) {
            self.captureKeys = captureKeys
            self.trackFocus = trackFocus
        }
    }

    private struct RawMove { var time: Double; var x: Double; var y: Double }
    private struct RawClick { var time: Double; var x: Double; var y: Double; var button: MouseButton; var down: Bool }
    private struct RawScroll { var time: Double; var x: Double; var y: Double; var dx: Double; var dy: Double }
    private struct RawCursor { var time: Double; var id: String }
    private struct RawKey { var time: Double; var shortcut: Bool }
    private struct RawFocus { var time: Double; var x: Double; var y: Double }

    /// Display frame in AppKit coordinates (origin bottom-left of the primary display).
    private let displayFrame: CGRect
    /// The same display in Quartz coordinates (origin top-left), which is what Accessibility uses.
    private let displayBounds: CGRect
    private let options: Options
    private let queue = DispatchQueue(label: "app.glide.input", qos: .userInteractive)
    private let focusQueue = DispatchQueue(label: "app.glide.focus", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var focusTimer: DispatchSourceTimer?
    private var monitors: [Any] = []

    private var moves: [RawMove] = []
    private var clicks: [RawClick] = []
    private var scrolls: [RawScroll] = []
    private var cursorChanges: [RawCursor] = []
    private var keys: [RawKey] = []
    private var focus: [RawFocus] = []
    private var cursorImages: [String: CursorImage] = [:]
    private var pendingPNGs: [String: Data] = [:]
    private var lastCursorKey: String?

    private let keyLock = NSLock()
    private var lastKeyTime = -Double.infinity

    public init(displayFrame: CGRect, displayBounds: CGRect, options: Options = Options()) {
        self.displayFrame = displayFrame
        self.displayBounds = displayBounds
        self.options = options
    }

    // MARK: Permissions

    public static var hasKeyboardAccess: Bool { CGPreflightListenEventAccess() }

    @discardableResult
    public static func requestKeyboardAccess() -> Bool { CGRequestListenEventAccess() }

    public static var hasAccessibilityAccess: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the person to Accessibility settings.
    public static func requestAccessibilityAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    // MARK: Start and stop

    public func start() {
        var mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
                                           .otherMouseDown, .otherMouseUp, .scrollWheel]
        if options.captureKeys { mask.insert(.keyDown) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event)
        }) {
            monitors.append(monitor)
        }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(8), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.poll() }
        timer.resume()
        self.timer = timer

        if options.captureKeys, options.trackFocus, Self.hasAccessibilityAccess {
            let focusTimer = DispatchSource.makeTimerSource(queue: focusQueue)
            focusTimer.schedule(deadline: .now(), repeating: .milliseconds(100), leeway: .milliseconds(20))
            focusTimer.setEventHandler { [weak self] in self?.pollFocus() }
            focusTimer.resume()
            self.focusTimer = focusTimer
        }
    }

    /// Stops recording and returns the log with times relative to `origin` (host-clock seconds).
    public func stop(origin: Double, writingCursorsTo folder: URL) -> (InputLog, [CursorImage]) {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        timer?.cancel()
        timer = nil
        focusTimer?.cancel()
        focusTimer = nil
        // Wait for a focus query that may still be running against a slow app.
        let focusSamples = focusQueue.sync { focus }

        return queue.sync {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (id, png) in pendingPNGs {
                try? png.write(to: folder.appendingPathComponent("\(id).png"))
            }

            func relative(_ time: Double) -> Double { max(0, time - origin) }
            // Samples before the first video frame are not part of the video, except the last one: that is where the
            // mouse was when the video began, which matters if it then stays still for a while.
            let before = moves.last { $0.time < origin }.map { [MouseSample(t: 0, x: $0.x, y: $0.y)] } ?? []
            let log = InputLog(
                moves: before + moves.filter { $0.time >= origin }.map { MouseSample(t: relative($0.time), x: $0.x, y: $0.y) },
                clicks: clicks.filter { $0.time >= origin }.map { ClickEvent(t: relative($0.time), x: $0.x, y: $0.y, button: $0.button, down: $0.down) },
                scrolls: scrolls.filter { $0.time >= origin }.map { ScrollEvent(t: relative($0.time), x: $0.x, y: $0.y, dx: $0.dx, dy: $0.dy) },
                cursors: cursorChanges.map { CursorChange(t: relative($0.time), id: $0.id) },
                keys: keys.filter { $0.time >= origin }.map { KeyEvent(t: relative($0.time), shortcut: $0.shortcut) },
                focus: focusSamples.filter { $0.time >= origin }.map { FocusSample(t: relative($0.time), x: $0.x, y: $0.y) }
            )
            return (log, Array(cursorImages.values).sorted { $0.id < $1.id })
        }
    }

    // MARK: Events

    private func normalized(_ location: CGPoint) -> (x: Double, y: Double) {
        (Double((location.x - displayFrame.minX) / displayFrame.width),
         Double(1 - (location.y - displayFrame.minY) / displayFrame.height))
    }

    private func handle(_ event: NSEvent) {
        // When it happened, not when it reached this app: events are handed over in step with the display, up to a frame late.
        let now = HostClock.now
        let time = abs(event.timestamp - now) < 0.25 ? event.timestamp : now
        let location = NSEvent.mouseLocation
        let (x, y) = normalized(location)
        let shortcut = event.type == .keyDown && !event.modifierFlags.isDisjoint(with: [.command, .control])
        queue.async { [self] in
            switch event.type {
            case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                clicks.append(RawClick(time: time, x: x, y: y, button: Self.button(for: event.type), down: true))
            case .leftMouseUp, .rightMouseUp, .otherMouseUp:
                clicks.append(RawClick(time: time, x: x, y: y, button: Self.button(for: event.type), down: false))
            case .scrollWheel:
                scrolls.append(RawScroll(time: time, x: x, y: y, dx: Double(event.scrollingDeltaX), dy: Double(event.scrollingDeltaY)))
            case .keyDown:
                // Only the moment is kept. The key itself is deliberately not read.
                keys.append(RawKey(time: time, shortcut: shortcut))
                if !shortcut {
                    keyLock.lock()
                    lastKeyTime = time
                    keyLock.unlock()
                }
            default:
                break
            }
        }
    }

    private static func button(for type: NSEvent.EventType) -> MouseButton {
        switch type {
        case .leftMouseDown, .leftMouseUp: return .left
        case .rightMouseDown, .rightMouseUp: return .right
        default: return .other
        }
    }

    private func poll() {
        let time = HostClock.now
        let (x, y) = normalized(NSEvent.mouseLocation)
        if let last = moves.last, last.x == x, last.y == y { /* unchanged */ } else {
            moves.append(RawMove(time: time, x: x, y: y))
        }
        recordCursorShape(at: time)
    }

    // MARK: Text caret

    /// Reads the caret position, but only while someone is typing: asking other apps about
    /// their focused element all the time would slow them down (browsers switch on their
    /// accessibility machinery the first time they are asked).
    private func pollFocus() {
        let now = HostClock.now
        keyLock.lock()
        let typingRecently = now - lastKeyTime < 2.0
        keyLock.unlock()
        guard typingRecently else { return }

        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return }
        let element = unsafeBitCast(value, to: AXUIElement.self)

        var rect = Self.caretRect(of: element)
        if rect == nil, let frame = Self.frame(of: element),
           // A control that fills most of the screen says nothing about where to look.
           frame.width * frame.height < displayBounds.width * displayBounds.height * 0.35 {
            rect = frame
        }
        guard let rect else { return }
        let x = Double((rect.midX - displayBounds.minX) / displayBounds.width)
        let y = Double((rect.midY - displayBounds.minY) / displayBounds.height)
        guard (0...1).contains(x), (0...1).contains(y) else { return }
        focus.append(RawFocus(time: now, x: x, y: y))
    }

    private static func caretRect(of element: AXUIElement) -> CGRect? {
        var range: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
              let range else { return nil }
        var bounds: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                         range, &bounds) == .success,
              let bounds, CFGetTypeID(bounds) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(unsafeBitCast(bounds, to: AXValue.self), .cgRect, &rect),
              rect.height > 0, rect.origin != .zero else { return nil }
        return rect
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size,
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &origin),
              AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &extent),
              extent.width > 0, extent.height > 0 else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    // MARK: Cursor shapes

    private func recordCursorShape(at time: Double) {
        guard let cursor = NSCursor.currentSystem else { return }
        let image = cursor.image
        let hotspot = cursor.hotSpot
        // Cheap change check first; the image is only rendered when size or hotspot changes.
        let key = "\(Int(image.size.width))x\(Int(image.size.height))@\(Int(hotspot.x)),\(Int(hotspot.y))"
        guard key != lastCursorKey || cursorChanges.isEmpty else { return }
        lastCursorKey = key

        // Ask for 4x so the sharpest representation the system has is used.
        var proposed = CGRect(x: 0, y: 0, width: image.size.width * 4, height: image.size.height * 4)
        guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
              let png = Self.pngData(cgImage) else { return }
        let id = "cursor-\(Self.fnv1a(png))"

        if cursorChanges.last?.id != id {
            cursorChanges.append(RawCursor(time: time, id: id))
        }
        if cursorImages[id] == nil {
            cursorImages[id] = CursorImage(id: id, file: "\(id).png", hotspotX: hotspot.x, hotspotY: hotspot.y,
                                           width: image.size.width, height: image.size.height)
            pendingPNGs[id] = png
        }
    }

    private static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    private static func fnv1a(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}
