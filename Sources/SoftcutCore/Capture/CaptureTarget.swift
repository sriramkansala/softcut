import AVFoundation
import CoreGraphics
import Foundation

/// What a recording captures.
public enum RecordMode: String, CaseIterable, Codable, Sendable {
    /// A whole display.
    case display
    /// One window. Other windows in front of it are left out of the video.
    case window
    /// A rectangle drawn on the screen.
    case area
}

/// A camera or microphone that can be chosen.
public struct InputDevice: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public enum CaptureDevices {
    public static func cameras() -> [InputDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera],
            mediaType: .video, position: .unspecified).devices
            .map { InputDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    public static func microphones() -> [InputDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices
            .map { InputDevice(id: $0.uniqueID, name: $0.localizedName) }
    }
}

/// Whether a camera or microphone is used, and which one was last picked.
public struct DeviceChoice: Equatable, Sendable {
    public var enabled: Bool
    public var chosen: String?

    public init(enabled: Bool, chosen: String?) {
        self.enabled = enabled
        self.chosen = chosen
    }

    /// The device to use now: none when off, the chosen one if it is still connected, otherwise the first available.
    public func resolved(in devices: [InputDevice]) -> String? {
        guard enabled else { return nil }
        if let chosen, devices.contains(where: { $0.id == chosen }) { return chosen }
        return devices.first?.id
    }

    /// Picks a device, or nil to turn it off. Turning it off remembers the last device for next time.
    public mutating func select(_ id: String?) {
        if let id { chosen = id }
        enabled = id != nil
    }
}

/// A window on screen, in the screen's own points with the origin at the top-left of the main display.
public struct WindowInfo: Identifiable, Equatable, Sendable {
    public let id: CGWindowID
    public let ownerName: String
    public let title: String
    public let bounds: CGRect
    public let ownerPID: pid_t

    public init(id: CGWindowID, ownerName: String, title: String, bounds: CGRect, ownerPID: pid_t) {
        self.id = id
        self.ownerName = ownerName
        self.title = title
        self.bounds = bounds
        self.ownerPID = ownerPID
    }

    public var label: String { title.isEmpty ? ownerName : "\(ownerName) — \(title)" }
}

public enum WindowCatalog {
    /// Windows smaller than this are not worth recording on their own (tooltips, badges).
    public static let minimumSide: CGFloat = 80

    /// The windows a person can pick, front to back. Menu bar, Dock and other system layers are left out,
    /// and so are the windows of the process named (Softcut's own recording bar and overlays).
    public static func onScreen(excludingPID pid: pid_t? = ProcessInfo.processInfo.processIdentifier) -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { parse($0, excludingPID: pid) }
    }

    /// Turns one entry of the system's window list into a window, or nil if it is not one to offer.
    static func parse(_ info: [String: Any], excludingPID pid: pid_t?) -> WindowInfo? {
        guard let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
              (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
              ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0.01,
              let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
              bounds.width >= minimumSide, bounds.height >= minimumSide else { return nil }
        let owner = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
        if let pid, owner == pid { return nil }
        return WindowInfo(id: number, ownerName: info[kCGWindowOwnerName as String] as? String ?? "",
                          title: info[kCGWindowName as String] as? String ?? "", bounds: bounds, ownerPID: owner)
    }

    /// The frontmost window under a point.
    public static func window(at point: CGPoint, in windows: [WindowInfo]) -> WindowInfo? {
        windows.first { $0.bounds.contains(point) }
    }
}

/// Where a recording points: which display, and optionally one window and the part of the display to show.
public struct CaptureTarget: Equatable, Sendable {
    public var displayID: CGDirectDisplayID
    public var windowID: CGWindowID?
    /// The part of the display the video starts out showing, or nil for all of it. The recording itself
    /// always keeps the whole display, so the edit can widen it again.
    public var crop: CropRect?

    public init(displayID: CGDirectDisplayID, windowID: CGWindowID? = nil, crop: CropRect? = nil) {
        self.displayID = displayID
        self.windowID = windowID
        self.crop = crop
    }

    /// A rectangle in global screen points as fractions of a display, from its top-left corner.
    public static func crop(for rect: CGRect, inDisplay bounds: CGRect) -> CropRect {
        guard bounds.width > 0, bounds.height > 0 else { return .full }
        let visible = rect.intersection(bounds)
        guard !visible.isNull, visible.width > 0, visible.height > 0 else { return .full }
        return CropRect(x: (visible.minX - bounds.minX) / bounds.width, y: (visible.minY - bounds.minY) / bounds.height,
                        width: visible.width / bounds.width, height: visible.height / bounds.height)
            .clamped(minimum: CropRect.minimumSize)
    }

    /// The display that shows most of a rectangle in global screen points.
    public static func display(showing rect: CGRect) -> CGDirectDisplayID {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        let best = ids.prefix(Int(count)).max { first, second in
            area(rect.intersection(CGDisplayBounds(first))) < area(rect.intersection(CGDisplayBounds(second)))
        }
        return best ?? CGMainDisplayID()
    }

    private static func area(_ rect: CGRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }

    /// The target for a rectangle someone drew.
    public static func area(_ rect: CGRect) -> CaptureTarget {
        let display = display(showing: rect)
        return CaptureTarget(displayID: display, crop: crop(for: rect, inDisplay: CGDisplayBounds(display)))
    }

    /// The target for one window.
    public static func window(_ window: WindowInfo) -> CaptureTarget {
        let display = display(showing: window.bounds)
        return CaptureTarget(displayID: display, windowID: window.id, crop: crop(for: window.bounds, inDisplay: CGDisplayBounds(display)))
    }
}
