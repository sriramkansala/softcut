import Foundation

extension KeyedDecodingContainer {
    /// Reads a value, falling back when the key is missing or unreadable. Used so that project files
    /// written by an older version keep loading after settings are added.
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}

public struct RGB: Equatable, Codable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    public init(hex: UInt32) {
        self.init(Double((hex >> 16) & 0xff) / 255, Double((hex >> 8) & 0xff) / 255, Double(hex & 0xff) / 255)
    }
}

/// The part of the screen that appears in the video, as fractions of the whole display.
public struct CropRect: Equatable, Codable, Sendable {
    public var x = 0.0
    public var y = 0.0
    public var width = 1.0
    public var height = 1.0

    public static let minimumSize = 0.1
    public static let full = CropRect()

    public init() {}

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self = clamped()
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = c.value(.x, x)
        y = c.value(.y, y)
        width = c.value(.width, width)
        height = c.value(.height, height)
        self = clamped()
    }

    public var isFull: Bool { x <= 0.0001 && y <= 0.0001 && width >= 0.9999 && height >= 0.9999 }

    /// Keeps the rectangle inside the display and at least a tenth of it in each direction.
    public func clamped(minimum: Double = CropRect.minimumSize) -> CropRect {
        var result = self
        result.width = min(max(width, minimum), 1)
        result.height = min(max(height, minimum), 1)
        result.x = min(max(x, 0), 1 - result.width)
        result.y = min(max(y, 0), 1 - result.height)
        return result
    }

    public var center: SIMD2<Double> { SIMD2(x + width / 2, y + height / 2) }
}

public enum CameraLayout: String, Codable, CaseIterable, Sendable {
    /// A small bubble over a corner of the screen.
    case bubble
    /// The screen and the camera side by side or one above the other.
    case splitRight, splitLeft, splitTop, splitBottom
    /// The person, cut out of their background, standing in a corner of the screen.
    case cutout

    public var title: String {
        switch self {
        case .bubble: return "Bubble"
        case .splitRight: return "Split, camera right"
        case .splitLeft: return "Split, camera left"
        case .splitTop: return "Split, camera above"
        case .splitBottom: return "Split, camera below"
        case .cutout: return "Cut-out"
        }
    }

    public var isSplit: Bool { [.splitRight, .splitLeft, .splitTop, .splitBottom].contains(self) }
}

public enum ZoomPresentation: String, Codable, CaseIterable, Sendable {
    /// The whole picture moves in.
    case camera
    /// A round magnifying lens follows the cursor while the picture stays put.
    case loupe

    public var title: String { self == .camera ? "Zoom in" : "Magnifier" }
}

public enum MaskKind: String, Codable, CaseIterable, Sendable {
    case blur, pixelate, fill

    public var title: String {
        switch self {
        case .blur: return "Blur"
        case .pixelate: return "Pixelate"
        case .fill: return "Cover"
        }
    }
}

/// A rectangle of the screen that is hidden for a while, for passwords, emails and the like.
public struct MaskRegion: Equatable, Codable, Identifiable, Sendable {
    public var id: UUID
    public var start: Double
    public var end: Double
    /// The rectangle, as fractions of the whole display, from its top-left corner.
    public var rect: CropRect
    public var kind: MaskKind
    /// How thoroughly it hides, from 0 to 1.
    public var strength: Double
    public var isDisabled: Bool

    public static let minimumLength = 0.3
    public static let minimumSize = 0.03

    public init(id: UUID = UUID(), start: Double, end: Double, rect: CropRect, kind: MaskKind = .blur, strength: Double = 0.7, isDisabled: Bool = false) {
        self.id = id
        self.start = start
        self.end = end
        self.rect = rect
        self.kind = kind
        self.strength = strength
        self.isDisabled = isDisabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        start = try c.decode(Double.self, forKey: .start)
        end = try c.decode(Double.self, forKey: .end)
        rect = c.value(.rect, CropRect(x: 0.35, y: 0.4, width: 0.3, height: 0.2))
        kind = c.value(.kind, .blur)
        strength = c.value(.strength, 0.7)
        isDisabled = c.value(.isDisabled, false)
    }
}

public enum CursorStyle: String, Codable, CaseIterable, Sendable {
    /// The recorded cursor, shape changes included, always drawn dark: black with a white outline.
    case dark
    /// The cursor exactly as it looked on screen, which can be white on a dark screen.
    case system
    case arrow, dot, ring, crosshair

    public var title: String {
        switch self {
        case .dark: return "Dark"
        case .system: return "Recorded"
        case .arrow: return "Arrow"
        case .dot: return "Dot"
        case .ring: return "Ring"
        case .crosshair: return "Cross"
        }
    }
}

public enum DeviceFrame: String, Codable, CaseIterable, Sendable {
    case none, browser, laptop, monitor

    public var title: String {
        switch self {
        case .none: return "None"
        case .browser: return "Browser"
        case .laptop: return "Laptop"
        case .monitor: return "Monitor"
        }
    }
}

public enum AspectChoice: String, Codable, CaseIterable, Sendable {
    case auto, wide, standard, square, portrait, vertical

    public var title: String {
        switch self {
        case .auto: return "Auto"
        case .wide: return "16:9"
        case .standard: return "4:3"
        case .square: return "1:1"
        case .portrait: return "4:5"
        case .vertical: return "9:16"
        }
    }

    /// Width divided by height, or nil to follow the shape of the screen.
    public var ratio: Double? {
        switch self {
        case .auto: return nil
        case .wide: return 16.0 / 9
        case .standard: return 4.0 / 3
        case .square: return 1
        case .portrait: return 4.0 / 5
        case .vertical: return 9.0 / 16
        }
    }
}

public enum BackgroundKind: String, Codable, CaseIterable, Sendable {
    case gradient, wallpaper, solid, image

    public var title: String {
        switch self {
        case .gradient: return "Gradient"
        case .wallpaper: return "Wallpaper"
        case .solid: return "Color"
        case .image: return "Image"
        }
    }
}

public struct BackgroundStyle: Equatable, Codable, Sendable {
    public var kind = BackgroundKind.gradient
    public var gradientTop = RGB(hex: 0x4776E6)
    public var gradientBottom = RGB(hex: 0x8E54E9)
    /// Direction of the gradient in degrees: 0 runs left to right, 90 top to bottom.
    public var angle = 45.0
    public var solid = RGB(hex: 0x1F2937)
    /// An image copied into the recording folder, so the project stays self-contained.
    public var imageFile: String?
    /// Blur as a fraction of the canvas width.
    public var imageBlur = 0.0
    /// One of the built-in wallpapers, used when `kind` is `.wallpaper`.
    public var wallpaperID = "nebula"

    public init() {}

    public static let white: BackgroundStyle = {
        var style = BackgroundStyle()
        style.kind = .solid
        style.solid = RGB(hex: 0xFFFFFF)
        return style
    }()

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        wallpaperID = c.value(.wallpaperID, wallpaperID)
        kind = c.value(.kind, kind)
        gradientTop = c.value(.gradientTop, gradientTop)
        gradientBottom = c.value(.gradientBottom, gradientBottom)
        angle = c.value(.angle, angle)
        solid = c.value(.solid, solid)
        imageFile = c.value(.imageFile, imageFile)
        imageBlur = c.value(.imageBlur, imageBlur)
    }
}

public enum WebcamShape: String, Codable, CaseIterable, Sendable {
    case circle, roundedSquare

    public var title: String { self == .circle ? "Circle" : "Rounded" }
}

public enum Corner: String, Codable, CaseIterable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight

    public var title: String {
        switch self {
        case .topLeft: return "Top left"
        case .topRight: return "Top right"
        case .bottomLeft: return "Bottom left"
        case .bottomRight: return "Bottom right"
        }
    }
}

public enum CaptionPosition: String, Codable, CaseIterable, Sendable {
    case bottom, top

    public var title: String { self == .bottom ? "Bottom" : "Top" }
}

/// A line of captions: some words shown from `start` to `end`, in the seconds of the recording they were spoken in.
/// Because it is tied to the recording, it follows the clip when the video is cut, moved or sped up.
public struct CaptionLine: Equatable, Codable, Identifiable, Sendable {
    public var id: UUID
    /// The recording it belongs to: nil for the project's own, or an attached recording's id.
    public var source: UUID?
    public var start: Double
    public var end: Double
    public var text: String

    public static let minimumLength = 0.3

    public init(id: UUID = UUID(), source: UUID? = nil, start: Double, end: Double, text: String) {
        self.id = id
        self.source = source
        self.start = start
        self.end = end
        self.text = text
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        source = try? c.decodeIfPresent(UUID.self, forKey: .source)
        start = try c.decode(Double.self, forKey: .start)
        end = try c.decode(Double.self, forKey: .end)
        text = c.value(.text, "")
    }
}

/// How the finished video looks. Sizes that scale with the video are fractions of the
/// output width so the look is the same at any resolution.
public struct RenderStyle: Equatable, Codable, Sendable {
    public var maxOutputWidth = 2560
    public var fps = 60
    public var aspect = AspectChoice.auto
    /// The part of the screen shown. Everything else in the recording is left out.
    public var crop = CropRect.full
    public var deviceFrame = DeviceFrame.none
    /// A 3D device to show the video inside, and how it arrives. It takes the place of the frame above.
    public var mockup: MockupChoice?
    public var cameraLayout = CameraLayout.bubble
    /// How much of the canvas the camera takes in a split layout.
    public var splitRatio = 0.34
    /// Height of the cut-out person, as a fraction of the screen's height.
    public var cutoutSize = 0.55
    /// Radius of the magnifier lens, as a fraction of the screen's width.
    public var loupeSize = 0.17
    /// How much the picture smears while the camera moves or zooms, from 0 (none) to 1.
    public var motionBlur = 0.5
    public var cursorStyle = CursorStyle.dark
    /// Space between the canvas edge and the screen, as a fraction of the output width.
    public var padding = 0.07
    public var cornerRadius = 0.012
    public var shadowOpacity = 0.35
    public var shadowBlur = 0.03
    /// How far the shadow is pushed from the screen, as a fraction of the output width.
    public var shadowDistance = 0.012
    /// Direction the shadow falls in degrees: 0 to the right, 90 straight down.
    public var shadowAngle = 90.0
    public var background = BackgroundStyle()
    /// What's behind a 3D device. Unset is pure white, and `background` comes back when the device is taken away.
    public var mockupBackground: BackgroundStyle?
    /// What's behind the picture right now, and what the Look pane edits.
    public var activeBackground: BackgroundStyle {
        get { mockup == nil ? background : mockupBackground ?? .white }
        set {
            if mockup == nil { background = newValue } else { mockupBackground = newValue }
        }
    }
    /// Cursor size relative to its real on-screen size.
    /// The size Screen Studio draws it at by default, measured from its export: about twice what Glide used before.
    public var cursorScale = 2.8
    public var showCursor = true
    /// The cursor leans a little as it moves sideways, like something being pulled along.
    public var cursorTilt = true
    /// Ripples at each click. Off by default, which keeps the picture clean.
    public var clickEffect = false
    public var clickColor = RGB(0.3, 0.6, 1.0)

    // Captions
    public var showCaptions = true
    /// Text height as a fraction of the output width.
    public var captionSize = 0.028
    public var captionPosition = CaptionPosition.bottom
    public var captionBackground = true
    public var captionBold = true
    public var captionColor = RGB(1, 1, 1)

    // Webcam
    public var showWebcam = true
    /// Diameter as a fraction of the screen width.
    public var webcamSize = 0.2
    /// Distance from the screen's edges, as a fraction of the screen width.
    public var webcamMargin = 0.03
    public var webcamMirror = false
    public var webcamShape = WebcamShape.circle
    public var webcamCorner = Corner.bottomRight
    /// Size multiplier while the camera is fully zoomed in, so the bubble stays out of the way.
    public var webcamZoomedScale = 0.8

    public init() {}

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        maxOutputWidth = c.value(.maxOutputWidth, maxOutputWidth)
        fps = c.value(.fps, fps)
        aspect = c.value(.aspect, aspect)
        crop = c.value(.crop, crop)
        deviceFrame = c.value(.deviceFrame, deviceFrame)
        mockup = c.value(.mockup, mockup)
        cameraLayout = c.value(.cameraLayout, cameraLayout)
        splitRatio = c.value(.splitRatio, splitRatio)
        cutoutSize = c.value(.cutoutSize, cutoutSize)
        loupeSize = c.value(.loupeSize, loupeSize)
        motionBlur = c.value(.motionBlur, motionBlur)
        cursorStyle = c.value(.cursorStyle, cursorStyle)
        padding = c.value(.padding, padding)
        cornerRadius = c.value(.cornerRadius, cornerRadius)
        shadowOpacity = c.value(.shadowOpacity, shadowOpacity)
        shadowBlur = c.value(.shadowBlur, shadowBlur)
        shadowDistance = c.value(.shadowDistance, shadowDistance)
        shadowAngle = c.value(.shadowAngle, shadowAngle)
        background = c.value(.background, background)
        mockupBackground = c.value(.mockupBackground, mockupBackground)
        cursorScale = c.value(.cursorScale, cursorScale)
        showCursor = c.value(.showCursor, showCursor)
        cursorTilt = c.value(.cursorTilt, cursorTilt)
        clickEffect = c.value(.clickEffect, clickEffect)
        clickColor = c.value(.clickColor, clickColor)
        showCaptions = c.value(.showCaptions, showCaptions)
        captionSize = c.value(.captionSize, captionSize)
        captionPosition = c.value(.captionPosition, captionPosition)
        captionBackground = c.value(.captionBackground, captionBackground)
        captionBold = c.value(.captionBold, captionBold)
        captionColor = c.value(.captionColor, captionColor)
        showWebcam = c.value(.showWebcam, showWebcam)
        webcamSize = c.value(.webcamSize, webcamSize)
        webcamMargin = c.value(.webcamMargin, webcamMargin)
        webcamMirror = c.value(.webcamMirror, webcamMirror)
        webcamShape = c.value(.webcamShape, webcamShape)
        webcamCorner = c.value(.webcamCorner, webcamCorner)
        webcamZoomedScale = c.value(.webcamZoomedScale, webcamZoomedScale)
    }
}

public struct EditSettings: Equatable, Codable, Sendable {
    public var style = RenderStyle()

    // Zoom
    public var autoZoom = true
    public var zoomScale = 2.0
    /// Off: zooms and camera moves travel at a steady pace, easing only briefly at each end. On: they start and end
    /// softly and move fastest in the middle.
    public var zoomEasing = false
    /// Seconds before a click at which its zoom begins. The zoom takes 0.7 s, so the picture is still before the click
    /// lands: the cursor has to be seen arriving before its sound and click effect, not after them.
    public var clickZoomLead = 0.85
    /// Seconds the zoom stays after the mouse button is let go.
    public var clickZoomHold = 2.5
    /// Zooms closer together than this become one, so the camera stays in and moves across instead of
    /// going out and coming back.
    public var zoomMergeGap = 2.0
    /// Clicks this close to the end of the recording are left alone: that is the click that stopped it.
    public var ignoreClicksAtEnd = 0.5

    // Typing
    /// Zoom in while typing, following the text caret when it is known.
    public var zoomOnTyping = true
    /// Gentler than the click zoom so a few lines of text stay in view.
    public var typingZoomScale = 1.8
    /// Key presses closer together than this belong to one stretch of typing.
    public var typingGap = 1.5
    /// A single stray key press (Return, Escape) is not typing.
    public var typingMinKeys = 3
    public var typingLeadIn = 0.5
    public var typingHold = 1.2
    /// Play stretches of typing faster, so the video does not wait for every key. Needs key times (Input
    /// Monitoring), and is skipped when a voice was recorded, so narration is never sped up.
    public var speedUpTyping = true
    public var typingSpeed = 3.0

    // Cursor
    public var smoothCursor = true

    // Trimming
    /// Remove idle time at the start and end of the recording. Skipped when audio was recorded.
    public var trimIdleEnds = true
    public var trimThreshold = 3.0
    public var trimMargin = 1.0
    /// Seconds cut from the very end, for the cursor's trip to the stop button.
    public var trimTail = 0.0
    /// Play stretches with no mouse activity faster. Off by default: a quiet mouse does not always
    /// mean nothing is happening on screen.
    public var speedUpIdle = false
    public var idleThreshold = 2.5
    public var idleSpeed = 4.0

    public init() {}

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        style = c.value(.style, style)
        autoZoom = c.value(.autoZoom, autoZoom)
        zoomScale = c.value(.zoomScale, zoomScale)
        zoomEasing = c.value(.zoomEasing, zoomEasing)
        clickZoomLead = c.value(.clickZoomLead, clickZoomLead)
        clickZoomHold = c.value(.clickZoomHold, clickZoomHold)
        zoomMergeGap = c.value(.zoomMergeGap, zoomMergeGap)
        ignoreClicksAtEnd = c.value(.ignoreClicksAtEnd, ignoreClicksAtEnd)
        zoomOnTyping = c.value(.zoomOnTyping, zoomOnTyping)
        typingZoomScale = c.value(.typingZoomScale, typingZoomScale)
        typingGap = c.value(.typingGap, typingGap)
        typingMinKeys = c.value(.typingMinKeys, typingMinKeys)
        typingLeadIn = c.value(.typingLeadIn, typingLeadIn)
        typingHold = c.value(.typingHold, typingHold)
        speedUpTyping = c.value(.speedUpTyping, speedUpTyping)
        typingSpeed = c.value(.typingSpeed, typingSpeed)
        smoothCursor = c.value(.smoothCursor, smoothCursor)
        trimIdleEnds = c.value(.trimIdleEnds, trimIdleEnds)
        trimThreshold = c.value(.trimThreshold, trimThreshold)
        trimMargin = c.value(.trimMargin, trimMargin)
        trimTail = c.value(.trimTail, trimTail)
        speedUpIdle = c.value(.speedUpIdle, speedUpIdle)
        idleThreshold = c.value(.idleThreshold, idleThreshold)
        idleSpeed = c.value(.idleSpeed, idleSpeed)
    }
}

public enum ZoomFollow: String, Codable, CaseIterable, Sendable {
    /// Follows the cursor, or the text caret while typing.
    case auto
    /// Stays on the chosen point.
    case fixed

    public var title: String { self == .auto ? "Follow cursor" : "Fixed point" }
}

public struct ZoomSegment: Equatable, Codable, Identifiable, Sendable {
    public var id: UUID
    public var start: Double
    public var end: Double
    /// Where the camera first aims, normalized to the display.
    public var focusX: Double
    public var focusY: Double
    /// Source time of the first click in the group; the camera is centered on the focus by then.
    public var focusTime: Double
    /// How far the camera zooms in during this segment.
    public var scale: Double
    public var follow: ZoomFollow
    public var isDisabled: Bool
    /// Jump to the zoom and back instead of easing in and out.
    public var instant: Bool
    public var presentation: ZoomPresentation

    public init(id: UUID = UUID(), start: Double, end: Double, focusX: Double, focusY: Double, focusTime: Double,
                scale: Double = 2.0, follow: ZoomFollow = .auto, isDisabled: Bool = false, instant: Bool = false,
                presentation: ZoomPresentation = .camera) {
        self.presentation = presentation
        self.instant = instant
        self.id = id
        self.start = start
        self.end = end
        self.focusX = focusX
        self.focusY = focusY
        self.focusTime = focusTime
        self.scale = scale
        self.follow = follow
        self.isDisabled = isDisabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        start = try c.decode(Double.self, forKey: .start)
        end = try c.decode(Double.self, forKey: .end)
        focusX = c.value(.focusX, 0.5)
        focusY = c.value(.focusY, 0.5)
        focusTime = c.value(.focusTime, start)
        scale = c.value(.scale, 2.0)
        follow = c.value(.follow, .auto)
        isDisabled = c.value(.isDisabled, false)
        instant = c.value(.instant, false)
        presentation = c.value(.presentation, .camera)
    }
}

public struct CameraState: Equatable, Sendable {
    public var scale: Double
    /// Center of the visible area, normalized to the display, origin top-left.
    public var centerX: Double
    public var centerY: Double
}

/// What one recording contributes to the video: its cursor path, the camera's movement, its clicks and the
/// zooms and masks that apply to it. All times are that recording's own seconds.
public struct SourcePlan {
    public var zooms: [ZoomSegment]
    public var clicks: [ClickEvent]
    public var masks: [MaskRegion]
    let cursorTrack: SampledTrack<SIMD2<Double>>
    let cameraTrack: SampledTrack<SIMD3<Double>>
    /// Captions spoken in this recording.
    public var captions: [CaptionLine] = []
    /// Left clicks with their releases, which push the cursor in.
    var presses: [AutoEditor.Press] = []

    /// How long before the button goes down the cursor starts to go in, and how long it takes to come back after the
    /// release. It is fully in at the moment of the click, as a real button is when it makes its sound.
    static let pressIn = 0.05, pressOut = 0.12

    /// How far the cursor is pushed in at a moment: 0 not at all, 1 fully.
    public func cursorPress(at time: Double) -> Double {
        var depth = 0.0
        for press in presses where time > press.down - Self.pressIn && time < press.up + Self.pressOut {
            let going = min((time - press.down + Self.pressIn) / Self.pressIn, 1)
            let coming = min((press.up + Self.pressOut - time) / Self.pressOut, 1)
            let amount = min(going, coming)
            depth = max(depth, amount * amount * (3 - 2 * amount))
        }
        return depth
    }

    /// How far the cursor leans at a moment, in radians, counterclockwise as drawn. It leans back from the
    /// direction it moves in, more the faster it goes, up to 15°.
    public func cursorTilt(at time: Double) -> Double {
        let dt = 1.0 / 30
        let speed = (cursor(at: time + dt).x - cursor(at: time - dt).x) / (2 * dt)
        return min(max(-speed * 0.35, -0.26), 0.26)
    }

    /// The caption showing at a moment, if any. If two overlap, the one that began last.
    public func caption(at time: Double) -> CaptionLine? {
        captions.last { time >= $0.start && time < $0.end && !$0.text.isEmpty }
    }

    /// Smoothed cursor position, normalized, origin top-left.
    public func cursor(at sourceTime: Double) -> SIMD2<Double> {
        let (i, f) = cursorTrack.index(at: sourceTime)
        let a = cursorTrack.samples[i]
        let b = cursorTrack.samples[min(i + 1, cursorTrack.samples.count - 1)]
        return a + (b - a) * f
    }

    public func camera(at sourceTime: Double, crop: CropRect) -> CameraState {
        let (i, f) = cameraTrack.index(at: sourceTime)
        let a = cameraTrack.samples[i]
        let b = cameraTrack.samples[min(i + 1, cameraTrack.samples.count - 1)]
        let v = a + (b - a) * f
        let scale = max(1, v.x)
        // Keep the visible area inside the cropped screen even while the spring is overshooting.
        let halfWidth = crop.width / (2 * scale)
        let halfHeight = crop.height / (2 * scale)
        return CameraState(scale: scale,
                           centerX: min(max(v.y, crop.x + halfWidth), crop.x + crop.width - halfWidth),
                           centerY: min(max(v.z, crop.y + halfHeight), crop.y + crop.height - halfHeight))
    }

    /// The magnifier lens at a moment: how much it magnifies, and how far it has grown in (0 to 1), or nil when none is showing.
    public func loupe(at time: Double) -> (scale: Double, progress: Double)? {
        guard let zoom = zooms.first(where: { $0.presentation == .loupe && !$0.isDisabled && time >= $0.start && time <= $0.end }) else { return nil }
        let fade = zoom.instant ? 0.05 : 0.35
        let edge = min((time - zoom.start) / fade, (zoom.end - time) / fade, 1)
        guard edge > 0 else { return nil }
        // Smoothstep, so the lens eases open and closed.
        return (zoom.scale, edge * edge * (3 - 2 * edge))
    }
}

/// Everything the renderer needs. The video is `timeMap` (clips from one or more recordings, end to end),
/// and each recording has its own `SourcePlan`.
public struct EditPlan {
    public var settings: EditSettings
    public var timeMap: TimeMap
    public var audio = AudioSettings()
    /// One plan per recording; the project's own recording is under the nil key.
    var sourcePlans: [UUID?: SourcePlan]

    init(settings: EditSettings, timeMap: TimeMap, audio: AudioSettings = AudioSettings(), sourcePlans: [UUID?: SourcePlan]) {
        self.settings = settings
        self.timeMap = timeMap
        self.audio = audio
        self.sourcePlans = sourcePlans
    }

    /// A plan for a single recording.
    init(settings: EditSettings, timeMap: TimeMap, zooms: [ZoomSegment], clicks: [ClickEvent], audio: AudioSettings = AudioSettings(),
         masks: [MaskRegion] = [], cursorTrack: SampledTrack<SIMD2<Double>>, cameraTrack: SampledTrack<SIMD3<Double>>) {
        self.init(settings: settings, timeMap: timeMap, audio: audio,
                  sourcePlans: [nil: SourcePlan(zooms: zooms, clicks: clicks, masks: masks, cursorTrack: cursorTrack, cameraTrack: cameraTrack)])
    }

    public var outputDuration: Double { timeMap.outputDuration }

    public func sourcePlan(_ source: UUID?) -> SourcePlan? { sourcePlans[source] }

    // The project's own recording, which is all there is when nothing has been attached.
    public var zooms: [ZoomSegment] { sourcePlans[nil]?.zooms ?? [] }
    public var clicks: [ClickEvent] { sourcePlans[nil]?.clicks ?? [] }
    public var masks: [MaskRegion] { sourcePlans[nil]?.masks ?? [] }
    public func cursor(at sourceTime: Double) -> SIMD2<Double> { cursor(source: nil, at: sourceTime) }
    public func camera(at sourceTime: Double) -> CameraState { camera(source: nil, at: sourceTime) }
    public func loupe(at time: Double) -> (scale: Double, progress: Double)? { sourcePlans[nil]?.loupe(at: time) }

    public func cursor(source: UUID?, at sourceTime: Double) -> SIMD2<Double> {
        sourcePlans[source]?.cursor(at: sourceTime) ?? SIMD2(0.5, 0.5)
    }

    public func camera(source: UUID?, at sourceTime: Double) -> CameraState {
        sourcePlans[source]?.camera(at: sourceTime, crop: settings.style.crop)
            ?? CameraState(scale: 1, centerX: settings.style.crop.center.x, centerY: settings.style.crop.center.y)
    }
}

/// A song or loop played under the video.
public struct BackingMusic: Equatable, Codable, Sendable {
    /// Where the file is. It stays where the person chose it.
    public var path: String
    public var name: String
    /// How loud it is next to the voice, from 0 to 1.
    public var volume: Double
    /// Repeat it if it is shorter than the video.
    public var loops: Bool

    public init(path: String, name: String, volume: Double = 0.3, loops: Bool = true) {
        self.path = path
        self.name = name
        self.volume = volume
        self.loops = loops
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        name = c.value(.name, URL(fileURLWithPath: path).lastPathComponent)
        volume = c.value(.volume, 0.3)
        loops = c.value(.loops, true)
    }
}

/// A voice recorded over the finished video in the editor.
public struct VoiceOver: Equatable, Codable, Identifiable, Sendable {
    public var id: UUID
    /// The sound file, kept in the recording's folder.
    public var path: String
    /// Where it starts in the finished video, in seconds.
    public var start: Double
    public var duration: Double
    public var volume: Double

    public init(id: UUID = UUID(), path: String, start: Double, duration: Double, volume: Double = 1) {
        self.id = id
        self.path = path
        self.start = start
        self.duration = duration
        self.volume = volume
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        path = try c.decode(String.self, forKey: .path)
        start = c.value(.start, 0)
        duration = try c.decode(Double.self, forKey: .duration)
        volume = c.value(.volume, 1)
    }

    public var end: Double { start + duration }
}

public struct AudioSettings: Equatable, Codable, Sendable {
    public var volume = 1.0
    public var muteMicrophone = false
    public var muteSystemAudio = false
    public var music: BackingMusic?
    /// A soft click sound at each mouse click.
    public var clickSounds = false
    public var clickVolume = 0.5
    public var voiceOvers: [VoiceOver] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        volume = c.value(.volume, volume)
        muteMicrophone = c.value(.muteMicrophone, muteMicrophone)
        muteSystemAudio = c.value(.muteSystemAudio, muteSystemAudio)
        music = try? c.decodeIfPresent(BackingMusic.self, forKey: .music)
        clickSounds = c.value(.clickSounds, clickSounds)
        clickVolume = c.value(.clickVolume, clickVolume)
        voiceOvers = c.value(.voiceOvers, voiceOvers)
    }

    /// The parts that change what sounds are in the video. Anything else (volumes, mutes) can change while it plays.
    var structure: AudioStructure {
        AudioStructure(musicPath: music?.path, musicLoops: music?.loops ?? false, clickSounds: clickSounds,
                       voiceOvers: voiceOvers.map { AudioStructure.Voice(id: $0.id, path: $0.path, start: $0.start, duration: $0.duration) })
    }
}

struct AudioStructure: Equatable {
    struct Voice: Equatable { let id: UUID; let path: String; let start: Double; let duration: Double }
    let musicPath: String?
    let musicLoops: Bool
    let clickSounds: Bool
    let voiceOvers: [Voice]
}
