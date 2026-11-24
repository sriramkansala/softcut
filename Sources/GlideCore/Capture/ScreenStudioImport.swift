import AVFoundation
import Foundation

/// Turns a Screen Studio project (`.screenstudio` folder) into a Glide recording, so the same recording can be edited
/// by both apps and their automatic edits compared. The project is only read, never changed.
///
/// What is kept: the screen video, mouse moves and clicks, cursor shapes, and the times of key presses. Which keys
/// were pressed is dropped, as Glide never keeps that. Screen Studio's own automatic zooms are saved beside the
/// recording as `screenstudio-zooms.json`, for comparison.
public enum ScreenStudioImport {
    /// A zoom from the Screen Studio project, in seconds of the recording.
    public struct ReferenceZoom: Codable, Equatable, Sendable {
        public var start: Double
        public var end: Double
        public var scale: Double
        public var type: String
    }

    public static func importProject(at project: URL, to folder: URL) async throws -> RecordingBundle {
        let recording = project.appendingPathComponent("recording", isDirectory: true)
        let metadata = try json(recording.appendingPathComponent("metadata.json"))
        guard let recorders = metadata["recorders"] as? [[String: Any]],
              let display = recorders.first(where: { $0["type"] as? String == "display" }),
              let session = (display["sessions"] as? [[String: Any]])?.first,
              let bounds = session["bounds"] as? [String: Any],
              let width = number(bounds["width"]), let height = number(bounds["height"]),
              let startMs = number(session["processTimeStartMs"]), let durationMs = number(session["durationMs"]),
              let playlist = session["outputFilename"] as? String else {
            throw GlideError.invalidRecording("the Screen Studio project has no screen recording")
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // The video is a playlist of fragments; joined in order they make one fragmented MP4 that AVFoundation reads.
        let video = folder.appendingPathComponent("screen.mp4")
        try joinFragments(playlist: recording.appendingPathComponent(playlist), into: video)
        let pixelWidth = try await videoWidth(video)

        func seconds(_ event: [String: Any]) -> Double? { number(event["processTimeMs"]).map { ($0 - startMs) / 1000 } }
        func position(_ event: [String: Any]) -> (Double, Double)? {
            guard let x = number(event["x"]), let y = number(event["y"]) else { return nil }
            return (x / width, y / height)
        }

        let input = (recorders.first { $0["type"] as? String == "input" }?["sessions"] as? [[String: Any]])?.first ?? [:]
        let moveEvents = try events(recording, input["mouseMovesFilename"] as? String ?? "mousemoves-0.json")
        let clickEvents = try events(recording, input["mouseClicksFilename"] as? String ?? "mouseclicks-0.json")
        let keyEvents = try events(recording, input["keyStrokesFilename"] as? String ?? "keystrokes-0.json")

        var log = InputLog()
        var shapes: [(t: Double, id: String)] = []
        for event in moveEvents {
            guard let t = seconds(event), let (x, y) = position(event) else { continue }
            log.moves.append(MouseSample(t: t, x: x, y: y))
            if let id = event["cursorId"] as? String { shapes.append((t, id)) }
        }
        for event in clickEvents {
            guard let t = seconds(event), let (x, y) = position(event), let type = event["type"] as? String,
                  type == "mouseDown" || type == "mouseUp" else { continue }
            let button: MouseButton = switch event["button"] as? String {
            case "left": .left
            case "right": .right
            default: .other
            }
            log.clicks.append(ClickEvent(t: t, x: x, y: y, button: button, down: type == "mouseDown"))
            if let id = event["cursorId"] as? String { shapes.append((t, id)) }
        }
        for event in keyEvents where event["type"] as? String == "keyDown" {
            guard let t = seconds(event) else { continue }
            let modifiers = (event["activeModifiers"] as? [String] ?? []).map { $0.lowercased() }
            let shortcut = modifiers.contains { $0.contains("command") || $0.contains("cmd") || $0.contains("control") || $0.contains("ctrl") }
            log.keys.append(KeyEvent(t: t, shortcut: shortcut))
        }
        log.moves.sort { $0.t < $1.t }
        log.clicks.sort { $0.t < $1.t }
        for shape in shapes.sorted(by: { $0.t < $1.t }) where log.cursors.last?.id != shape.id {
            log.cursors.append(CursorChange(t: shape.t, id: shape.id))
        }

        // Cursor pictures, with their hotspots and sizes in points.
        var cursors: [CursorImage] = []
        let cursorsFolder = folder.appendingPathComponent("cursors", isDirectory: true)
        try FileManager.default.createDirectory(at: cursorsFolder, withIntermediateDirectories: true)
        let used = Set(log.cursors.map(\.id))
        if let list = try? JSONSerialization.jsonObject(with: Data(contentsOf: recording.appendingPathComponent("cursors.json"))) as? [[String: Any]] {
            for entry in list {
                guard let id = entry["id"] as? String, used.contains(id),
                      let hotspot = entry["hotSpot"] as? [String: Any], let size = entry["standardSize"] as? [String: Any],
                      let hx = number(hotspot["x"]), let hy = number(hotspot["y"]),
                      let w = number(size["width"]), let h = number(size["height"]) else { continue }
                let source = recording.appendingPathComponent("cursors/\(id).png")
                guard FileManager.default.fileExists(atPath: source.path) else { continue }
                let target = cursorsFolder.appendingPathComponent("\(id).png")
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.copyItem(at: source, to: target)
                cursors.append(CursorImage(id: id, file: "\(id).png", hotspotX: hx, hotspotY: hy, width: w, height: h))
            }
        }

        let manifest = RecordingManifest(
            createdAt: number(session["unixStartMs"]).map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date(),
            displayID: UInt32(number((display["configuration"] as? [String: Any])?["displayId"]) ?? 0),
            displayWidth: width, displayHeight: height, pixelScale: Double(pixelWidth) / width,
            videoFile: "screen.mp4", duration: durationMs / 1000,
            hasSystemAudio: false, hasMicrophone: false, source: "screenstudio",
            keysCaptured: (input["keyStrokesFilename"] as? String) != nil, caretTracked: false)
        let bundle = RecordingBundle(folder: folder, manifest: manifest, input: log, cursors: cursors)
        try bundle.save()

        let reference = try referenceZooms(project)
        try JSONEncoder().encode(reference).write(to: folder.appendingPathComponent("screenstudio-zooms.json"))
        return bundle
    }

    /// The zooms Screen Studio made for its project. Its backup file holds the edit as first made, before any changes.
    public static func referenceZooms(_ project: URL) throws -> [ReferenceZoom] {
        let backup = project.appendingPathComponent("project.json.bak")
        let file = FileManager.default.fileExists(atPath: backup.path) ? backup : project.appendingPathComponent("project.json")
        let root = try json(file)
        guard let scenes = (root["json"] as? [String: Any])?["scenes"] as? [[String: Any]] else { return [] }
        return scenes.flatMap { ($0["zooms"] as? [[String: Any]]) ?? [] }.compactMap { zoom in
            guard let start = number(zoom["sourceStartMs"]), let end = number(zoom["sourceEndMs"]) else { return nil }
            return ReferenceZoom(start: start / 1000, end: end / 1000, scale: number(zoom["zoom"]) ?? 2, type: zoom["type"] as? String ?? "")
        }
    }

    // MARK: Helpers

    private static func json(_ url: URL) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
            throw GlideError.invalidRecording("\(url.lastPathComponent) is not what Softcut expected")
        }
        return object
    }

    private static func events(_ folder: URL, _ name: String) throws -> [[String: Any]] {
        let url = folder.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return (try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]]) ?? []
    }

    private static func number(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }

    static func joinFragments(playlist: URL, into output: URL) throws {
        let text = try String(contentsOf: playlist, encoding: .utf8)
        let folder = playlist.deletingLastPathComponent()
        var files: [String] = []
        for line in text.split(whereSeparator: \.isNewline).map(String.init) {
            if line.hasPrefix("#EXT-X-MAP:"), let range = line.range(of: #"URI="([^"]+)""#, options: .regularExpression) {
                files.insert(String(line[range]).replacingOccurrences(of: "URI=", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "\"")), at: 0)
            } else if !line.hasPrefix("#"), !line.trimmingCharacters(in: .whitespaces).isEmpty {
                files.append(line.trimmingCharacters(in: .whitespaces))
            }
        }
        guard !files.isEmpty else { throw GlideError.invalidRecording("the screen recording playlist is empty") }
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        for file in files { try handle.write(contentsOf: Data(contentsOf: folder.appendingPathComponent(file))) }
    }

    private static func videoWidth(_ url: URL) async throws -> Int {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw GlideError.invalidRecording("the joined screen recording has no video")
        }
        return Int(try await track.load(.naturalSize).width)
    }
}
