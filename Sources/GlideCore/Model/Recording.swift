import Foundation

/// Describes one raw recording on disk. Everything the renderer needs to turn the
/// raw capture into a finished video is in this folder:
///
///     manifest.json        this struct
///     screen.mov           screen video without the cursor (+ system audio / mic tracks)
///     input.json           mouse moves, clicks, scrolls and cursor-shape changes
///     cursors/             one PNG per cursor shape seen, plus cursors.json
public struct RecordingManifest: Codable, Equatable {
    public var formatVersion: Int
    public var createdAt: Date
    public var displayID: UInt32
    /// Recorded display size in points.
    public var displayWidth: Double
    public var displayHeight: Double
    /// Video pixels per display point.
    public var pixelScale: Double
    public var videoFile: String
    /// Seconds from the first video frame to the moment recording stopped.
    public var duration: Double
    public var hasSystemAudio: Bool
    public var hasMicrophone: Bool
    /// Where the recording came from: "glide" or an importer name.
    public var source: String
    /// Separate webcam video, if one was recorded.
    public var webcamFile: String?
    /// Webcam first-frame time minus screen first-frame time, in seconds. Negative when the
    /// camera started first. Webcam time = screen time - offset.
    public var webcamOffset: Double?
    /// Whether key-press times were being recorded. When false, typing is invisible to the editor,
    /// so it must not treat a quiet mouse as an idle stretch to trim. Nil in older recordings.
    public var keysCaptured: Bool?
    /// Whether the text caret was being tracked while typing.
    public var caretTracked: Bool?

    public init(createdAt: Date = Date(), displayID: UInt32, displayWidth: Double, displayHeight: Double,
                pixelScale: Double, videoFile: String = "screen.mov", duration: Double,
                hasSystemAudio: Bool, hasMicrophone: Bool, source: String = "glide",
                webcamFile: String? = nil, webcamOffset: Double? = nil,
                keysCaptured: Bool? = nil, caretTracked: Bool? = nil) {
        self.webcamFile = webcamFile
        self.webcamOffset = webcamOffset
        self.keysCaptured = keysCaptured
        self.caretTracked = caretTracked
        self.formatVersion = 1
        self.createdAt = createdAt
        self.displayID = displayID
        self.displayWidth = displayWidth
        self.displayHeight = displayHeight
        self.pixelScale = pixelScale
        self.videoFile = videoFile
        self.duration = duration
        self.hasSystemAudio = hasSystemAudio
        self.hasMicrophone = hasMicrophone
        self.source = source
    }
}

// All times are seconds relative to the first video frame. All positions are
// normalized to the recorded display: (0, 0) is its top-left corner, (1, 1) its
// bottom-right. Values outside 0...1 mean the cursor was on another display.

public struct MouseSample: Codable, Equatable {
    public var t: Double
    public var x: Double
    public var y: Double

    public init(t: Double, x: Double, y: Double) {
        self.t = t
        self.x = x
        self.y = y
    }
}

public enum MouseButton: String, Codable {
    case left, right, other
}

public struct ClickEvent: Codable, Equatable {
    public var t: Double
    public var x: Double
    public var y: Double
    public var button: MouseButton
    public var down: Bool

    public init(t: Double, x: Double, y: Double, button: MouseButton = .left, down: Bool) {
        self.t = t
        self.x = x
        self.y = y
        self.button = button
        self.down = down
    }
}

public struct ScrollEvent: Codable, Equatable {
    public var t: Double
    public var x: Double
    public var y: Double
    public var dx: Double
    public var dy: Double

    public init(t: Double, x: Double, y: Double, dx: Double, dy: Double) {
        self.t = t
        self.x = x
        self.y = y
        self.dx = dx
        self.dy = dy
    }
}

/// The cursor shape changed to `id` at time `t`.
public struct CursorChange: Codable, Equatable {
    public var t: Double
    public var id: String

    public init(t: Double, id: String) {
        self.t = t
        self.id = id
    }
}

/// A key was pressed. Only the time is kept, never which key: the recording is used to find
/// out when someone is typing, not what they typed. `shortcut` is true when Command or
/// Control was held, which is not text entry.
public struct KeyEvent: Codable, Equatable {
    public var t: Double
    public var shortcut: Bool

    public init(t: Double, shortcut: Bool = false) {
        self.t = t
        self.shortcut = shortcut
    }
}

/// Where the text caret (or, failing that, the focused control) was, normalized to the display.
public struct FocusSample: Codable, Equatable {
    public var t: Double
    public var x: Double
    public var y: Double

    public init(t: Double, x: Double, y: Double) {
        self.t = t
        self.x = x
        self.y = y
    }
}

public struct InputLog: Codable, Equatable {
    public var moves: [MouseSample]
    public var clicks: [ClickEvent]
    public var scrolls: [ScrollEvent]
    public var cursors: [CursorChange]
    public var keys: [KeyEvent]
    public var focus: [FocusSample]

    public init(moves: [MouseSample] = [], clicks: [ClickEvent] = [], scrolls: [ScrollEvent] = [],
                cursors: [CursorChange] = [], keys: [KeyEvent] = [], focus: [FocusSample] = []) {
        self.moves = moves
        self.clicks = clicks
        self.scrolls = scrolls
        self.cursors = cursors
        self.keys = keys
        self.focus = focus
    }

    // Recordings made before keys and focus existed have neither field.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        moves = try container.decode([MouseSample].self, forKey: .moves)
        clicks = try container.decode([ClickEvent].self, forKey: .clicks)
        scrolls = try container.decode([ScrollEvent].self, forKey: .scrolls)
        cursors = try container.decode([CursorChange].self, forKey: .cursors)
        keys = try container.decodeIfPresent([KeyEvent].self, forKey: .keys) ?? []
        focus = try container.decodeIfPresent([FocusSample].self, forKey: .focus) ?? []
    }
}

/// One cursor shape. Sizes and hotspot are in points, hotspot measured from the
/// image's top-left corner.
public struct CursorImage: Codable, Equatable {
    public var id: String
    public var file: String
    public var hotspotX: Double
    public var hotspotY: Double
    public var width: Double
    public var height: Double

    public init(id: String, file: String, hotspotX: Double, hotspotY: Double, width: Double, height: Double) {
        self.id = id
        self.file = file
        self.hotspotX = hotspotX
        self.hotspotY = hotspotY
        self.width = width
        self.height = height
    }
}

public struct RecordingBundle {
    public let folder: URL
    public var manifest: RecordingManifest
    public var input: InputLog
    public var cursors: [CursorImage]

    public init(folder: URL, manifest: RecordingManifest, input: InputLog, cursors: [CursorImage]) {
        self.folder = folder
        self.manifest = manifest
        self.input = input
        self.cursors = cursors
    }

    public var videoURL: URL { folder.appendingPathComponent(manifest.videoFile) }
    public var webcamURL: URL? {
        guard let file = manifest.webcamFile else { return nil }
        let url = folder.appendingPathComponent(file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    public var cursorsFolder: URL { folder.appendingPathComponent("cursors", isDirectory: true) }

    public static func load(from folder: URL) throws -> RecordingBundle {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(RecordingManifest.self, from: Data(contentsOf: folder.appendingPathComponent("manifest.json")))
        let input = try decoder.decode(InputLog.self, from: Data(contentsOf: folder.appendingPathComponent("input.json")))
        let cursorsFile = folder.appendingPathComponent("cursors/cursors.json")
        let cursors = FileManager.default.fileExists(atPath: cursorsFile.path)
            ? try decoder.decode([CursorImage].self, from: Data(contentsOf: cursorsFile))
            : []
        return RecordingBundle(folder: folder, manifest: manifest, input: input, cursors: cursors)
    }

    public func save() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try FileManager.default.createDirectory(at: cursorsFolder, withIntermediateDirectories: true)
        try encoder.encode(manifest).write(to: folder.appendingPathComponent("manifest.json"))
        try encoder.encode(input).write(to: folder.appendingPathComponent("input.json"))
        try encoder.encode(cursors).write(to: cursorsFolder.appendingPathComponent("cursors.json"))
    }
}

public enum GlideError: LocalizedError {
    case noDisplay
    case noFramesCaptured
    case writerFailed(String)
    case noVideoTrack
    case invalidRecording(String)
    case cameraUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .cameraUnavailable(let detail): return "The webcam could not be used: \(detail)"
        case .noDisplay: return "The selected display is not available."
        case .noFramesCaptured: return "No video frames were captured. Check that Screen Recording permission is turned on."
        case .writerFailed(let detail): return "Writing the video failed: \(detail)"
        case .noVideoTrack: return "The recording has no video track."
        case .invalidRecording(let detail): return "The recording could not be read: \(detail)"
        }
    }
}
