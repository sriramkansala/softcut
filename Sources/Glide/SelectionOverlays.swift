import AppKit
import GlideCore

/// Full-screen layers for choosing what to record: hover over a window and click it, or drag a rectangle.
/// Esc or a right click cancels. Rectangles are in global screen points with the origin at the top-left
/// of the main display, which is what `CGDisplayBounds` and `WindowInfo` use.
@MainActor
enum SelectionOverlay {
    static func pickWindow() async -> WindowInfo? {
        await withCheckedContinuation { continuation in
            var session: Session?
            session = Session(kind: .window) { result in
                session?.close()
                session = nil
                continuation.resume(returning: result.window)
            }
            session?.open()
        }
    }

    static func drawArea() async -> CGRect? {
        await withCheckedContinuation { continuation in
            var session: Session?
            session = Session(kind: .area) { result in
                session?.close()
                session = nil
                continuation.resume(returning: result.area)
            }
            session?.open()
        }
    }

    fileprivate enum Kind { case window, area }

    fileprivate struct Outcome {
        var window: WindowInfo?
        var area: CGRect?
    }

    /// AppKit's global points have the origin at the bottom-left of the main screen; the screen list uses the top-left.
    fileprivate static func toTopLeft(_ rect: CGRect) -> CGRect {
        let height = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }

    fileprivate static func toAppKit(_ rect: CGRect) -> CGRect { toTopLeft(rect) }

    @MainActor
    fileprivate final class Session {
        let kind: Kind
        private let finish: (Outcome) -> Void
        private var windows: [OverlayWindow] = []
        private let catalog: [WindowInfo]
        private var done = false

        /// What is highlighted or being drawn, in AppKit global points.
        private(set) var highlight: CGRect?
        private(set) var hovered: WindowInfo?
        private var dragStart: CGPoint?

        init(kind: Kind, finish: @escaping (Outcome) -> Void) {
            self.kind = kind
            self.finish = finish
            self.catalog = kind == .window ? WindowCatalog.onScreen() : []
        }

        func open() {
            for screen in NSScreen.screens {
                let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
                window.level = .screenSaver
                window.isOpaque = false
                window.backgroundColor = .clear
                window.hasShadow = false
                window.isReleasedWhenClosed = false
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
                window.contentView = OverlayView(session: self, frame: CGRect(origin: .zero, size: screen.frame.size))
                window.setFrame(screen.frame, display: true)
                window.orderFrontRegardless()
                windows.append(window)
            }
            NSApp.activate(ignoringOtherApps: true)
            windows.first { $0.frame.contains(NSEvent.mouseLocation) }?.makeKeyAndOrderFront(nil)
            moved(to: NSEvent.mouseLocation)
        }

        func close() {
            windows.forEach { $0.orderOut(nil); $0.contentView = nil }
            windows = []
            NSCursor.arrow.set()
        }

        private func complete(_ outcome: Outcome) {
            guard !done else { return }
            done = true
            finish(outcome)
        }

        func cancel() { complete(Outcome()) }

        private func redraw() { windows.forEach { $0.contentView?.needsDisplay = true } }

        // MARK: Mouse

        func moved(to point: CGPoint) {
            guard kind == .window else { return }
            // The catalog is in top-left points, the mouse in AppKit points.
            let screenHeight = NSScreen.screens.first?.frame.height ?? 0
            let found = WindowCatalog.window(at: CGPoint(x: point.x, y: screenHeight - point.y), in: catalog)
            hovered = found
            highlight = found.map { toAppKit($0.bounds) }
            redraw()
        }

        func pressed(at point: CGPoint) {
            switch kind {
            case .window:
                if let hovered { complete(Outcome(window: hovered)) }
            case .area:
                dragStart = point
                highlight = CGRect(origin: point, size: .zero)
                redraw()
            }
        }

        func dragged(to point: CGPoint) {
            guard kind == .area, let start = dragStart else { return }
            highlight = CGRect(x: min(start.x, point.x), y: min(start.y, point.y), width: abs(point.x - start.x), height: abs(point.y - start.y))
            redraw()
        }

        func released() {
            guard kind == .area, dragStart != nil else { return }
            dragStart = nil
            if let highlight, highlight.width >= 60, highlight.height >= 60 {
                complete(Outcome(area: toTopLeft(highlight)))
            } else {
                // Too small to be what was meant: start over.
                highlight = nil
                redraw()
            }
        }
    }

    @MainActor
    private final class OverlayWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    @MainActor
    private final class OverlayView: NSView {
        private unowned let session: Session

        init(session: Session, frame: CGRect) {
            self.session = session
            super.init(frame: frame)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
        }

        required init?(coder: NSCoder) { fatalError() }

        override var acceptsFirstResponder: Bool { true }
        override var isFlipped: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: session.kind == .area ? .crosshair : .pointingHand) }

        override func mouseMoved(with event: NSEvent) { session.moved(to: NSEvent.mouseLocation) }
        override func mouseDown(with event: NSEvent) { session.pressed(at: NSEvent.mouseLocation) }
        override func mouseDragged(with event: NSEvent) { session.dragged(to: NSEvent.mouseLocation) }
        override func mouseUp(with event: NSEvent) { session.released() }
        override func rightMouseDown(with event: NSEvent) { session.cancel() }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { session.cancel() } else { super.keyDown(with: event) }
        }

        override func draw(_ dirtyRect: NSRect) {
            guard let window else { return }
            // Global highlight rectangle in this screen's own coordinates.
            let local = session.highlight.map { window.convertFromScreen($0) }

            let shade = NSBezierPath(rect: bounds)
            if let local { shade.append(NSBezierPath(roundedRect: local, xRadius: 8, yRadius: 8)); shade.windingRule = .evenOdd }
            NSColor.black.withAlphaComponent(session.kind == .area && local == nil ? 0.25 : 0.42).setFill()
            shade.fill()

            guard let local, local.width > 1 else {
                drawHint(session.kind == .window ? "Click a window to record it. Esc to cancel." : "Drag to choose what to record. Esc to cancel.")
                return
            }
            // Glide's brand purple, the one accent in its interface.
            let outline = NSBezierPath(roundedRect: local, xRadius: 8, yRadius: 8)
            NSColor(srgbRed: 0x7C / 255, green: 0x5C / 255, blue: 1, alpha: 1).setStroke()
            outline.lineWidth = 2
            outline.stroke()

            switch session.kind {
            case .window:
                if let hovered = session.hovered { drawLabel(hovered.label, around: local) }
            case .area:
                if let global = session.highlight {
                    drawLabel("\(Int(global.width)) × \(Int(global.height))", around: local)
                }
            }
        }

        private func drawHint(_ text: String) {
            let point = NSPoint(x: bounds.midX, y: bounds.maxY - 90)
            draw(text, centeredAt: point, size: 15)
        }

        private func drawLabel(_ text: String, around rect: CGRect) {
            draw(text, centeredAt: NSPoint(x: rect.midX, y: rect.midY), size: 14)
        }

        /// A label drawn like Fluid's tooltip: dark text on the light ink color, with 8 pt corners.
        private func draw(_ text: String, centeredAt center: NSPoint, size: CGFloat) {
            let ink = NSColor(srgbRed: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF5 / 255, alpha: 1)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: size, weight: NSFont.Weight(0.265)),
                .foregroundColor: NSColor(srgbRed: 0x17 / 255, green: 0x17 / 255, blue: 0x17 / 255, alpha: 1),
            ]
            let string = NSAttributedString(string: text, attributes: attributes)
            let textSize = string.size()
            let plate = CGRect(x: center.x - textSize.width / 2 - 12, y: center.y - textSize.height / 2 - 6,
                               width: textSize.width + 24, height: textSize.height + 12)
            ink.setFill()
            NSBezierPath(roundedRect: plate, xRadius: 8, yRadius: 8).fill()
            string.draw(at: NSPoint(x: plate.minX + 12, y: plate.minY + 6))
        }
    }
}
