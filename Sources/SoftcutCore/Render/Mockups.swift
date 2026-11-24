import CoreGraphics
import Foundation
import simd

/// Which device a video is shown in, and how it arrives. Stored with the project's look.
public struct MockupChoice: Equatable, Codable, Sendable {
    public var deviceID: String
    public var motionID: String

    public init(deviceID: String, motionID: String) {
        self.deviceID = deviceID
        self.motionID = motionID
    }

    private enum CodingKeys: String, CodingKey {
        case deviceID, motionID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        motionID = try container.decode(String.self, forKey: .motionID)
        let saved = try container.decode(String.self, forKey: .deviceID)
        // Earlier projects may name the models these replaced.
        deviceID = ["iphone-17-pro": "iphone-18-pro", "iphone-17-pro-max": "iphone-18-pro-max"][saved] ?? saved
    }
}

public enum MockupFamily: String, Codable, Sendable, CaseIterable {
    case macbook, iphone

    public var title: String { self == .macbook ? "MacBook" : "iPhone" }

    /// The canvas's shape when the aspect ratio is Auto: a laptop sits well in a wide frame, a phone in a square one.
    var automaticAspect: Double { self == .macbook ? 1.6 : 1 }
}

/// Where a device is at one moment of a motion, in the coordinates of its model.
public struct MockupPose: Equatable, Sendable {
    public var position: SIMD3<Float>
    public var rotation: simd_quatf
    /// The lid's turn about the hinge, in radians. Zero is closed.
    public var lid: Float
    /// How awake the display is: dark while a laptop's lid is shut, full once it is open.
    public var display: Float
}

/// A predefined movement of a device, keyed in Blender and baked to 60 samples a second: an arrival, then a very slow
/// drift that keeps the picture alive however long the video runs.
public struct MockupMotion: Decodable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    /// When the arrival has come to rest. The motion loops from here to `duration`, which is one cycle of the drift.
    public let settle: Double
    public let duration: Double
    let positions: [[Float]]
    let rotations: [[Float]]
    let lid: [Float]
    let display: [Float]

    /// The pose at a moment of the video.
    public func pose(at time: Double) -> MockupPose {
        let count = positions.count
        guard count > 0 else { return MockupPose(position: .zero, rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), lid: 0, display: 1) }
        var t = max(0, time)
        if t > duration, duration > settle { t = settle + (t - settle).truncatingRemainder(dividingBy: duration - settle) }
        let place = min(t * 60, Double(count - 1))
        let low = Int(place)
        let high = min(low + 1, count - 1)
        let mix = Float(place - Double(low))
        func quat(_ q: [Float]) -> simd_quatf { simd_quatf(ix: q[1], iy: q[2], iz: q[3], r: q[0]) }
        func vector(_ p: [Float]) -> SIMD3<Float> { SIMD3(p[0], p[1], p[2]) }
        return MockupPose(position: vector(positions[low]) + (vector(positions[high]) - vector(positions[low])) * mix,
                          rotation: simd_slerp(quat(rotations[low]), quat(rotations[high]), mix),
                          lid: lid[low] + (lid[high] - lid[low]) * mix,
                          display: display[low] + (display[high] - display[low]) * mix)
    }
}

/// One device: what the Blender build measured about it, and its motions.
public struct MockupDevice: Decodable, Identifiable, Sendable {
    public struct Screen: Decodable, Sendable {
        public let width: Double
        public let height: Double
        /// Bottom left, bottom right, top left and top right, in the resting pose.
        let corners: [[Double]]
    }

    struct Bounds: Decodable, Sendable {
        let min: [Double]
        let max: [Double]
    }

    public let id: String
    public let name: String
    public let family: MockupFamily
    public let finish: String
    public let screen: Screen
    let bounds: Bounds
    /// How strongly the studio lights this finish: a photographer gives silver less light than black.
    public let exposure: Double
    /// How much of the screen's light its deck shows, which depends on how much the finish reflects. Phones have none.
    public let glow: Double
    public let motions: [MockupMotion]

    public func motion(id: String) -> MockupMotion? { motions.first { $0.id == id } }

    /// The width of the screen divided by its height.
    public var screenAspect: Double { screen.width / screen.height }

    /// The first motion that opens or brings in the device, used when a device is first chosen.
    public var defaultMotion: MockupMotion? { motions.first }
}

/// The devices that ship with Softcut: `Mockups/` beside the app's resources, or in the source tree while developing.
public final class MockupLibrary: @unchecked Sendable {
    public struct Entry: Decodable, Identifiable, Sendable {
        public let id: String
        public let name: String
        public let family: MockupFamily
        public let finish: String
    }

    private struct Index: Decodable { let devices: [Entry] }

    public static let shared = MockupLibrary(folder: MockupLibrary.defaultFolder())

    public let folder: URL?
    public let entries: [Entry]
    private let lock = NSLock()
    private var loaded: [String: MockupDevice] = [:]

    public init(folder: URL?) {
        self.folder = folder
        let index = folder.flatMap { try? Data(contentsOf: $0.appendingPathComponent("index.json")) }
            .flatMap { try? JSONDecoder().decode(Index.self, from: $0) }
        entries = index?.devices ?? []
    }

    private static func defaultFolder() -> URL? {
        let manager = FileManager.default
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Mockups"),
           manager.fileExists(atPath: bundled.appendingPathComponent("index.json").path) {
            return bundled
        }
        // Sources/SoftcutCore/Render/Mockups.swift → the package's own Mockups folder.
        let source = URL(fileURLWithPath: #filePath)
        let package = source.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let local = package.appendingPathComponent("Mockups")
        return manager.fileExists(atPath: local.appendingPathComponent("index.json").path) ? local : nil
    }

    public func entries(in family: MockupFamily) -> [Entry] { entries.filter { $0.family == family } }

    public func device(id: String) -> MockupDevice? {
        lock.lock()
        defer { lock.unlock() }
        if let device = loaded[id] { return device }
        guard let folder, let data = try? Data(contentsOf: folder.appendingPathComponent(id).appendingPathComponent("device.json")),
              let device = try? JSONDecoder().decode(MockupDevice.self, from: data) else { return nil }
        loaded[id] = device
        return device
    }

    public func modelURL(id: String) -> URL? { folder?.appendingPathComponent(id).appendingPathComponent("model.usdz") }
    public func thumbnailURL(id: String) -> URL? { folder?.appendingPathComponent(id).appendingPathComponent("thumbnail.png") }
}

/// Where the camera stands so that a device at rest fits a canvas, and where things land on the canvas from there.
/// All in the model's coordinates: +X right, +Z up, with the viewer at -Y looking toward +Y.
public struct MockupStage: Equatable, Sendable {
    public let canvas: CGSize
    /// How narrow the lens is: 1 / tan(half the vertical field of view).
    public let focal: Double
    public let centerX: Double
    public let centerZ: Double
    public let distance: Double
    let corners: [SIMD3<Double>]

    /// A long lens, so that a device looks like a product shot, not a wide-angle selfie.
    static let fieldOfViewDegrees = 14.0

    public static func fit(_ device: MockupDevice, canvas: CGSize, padding: Double) -> MockupStage {
        let focal = 1 / tan(fieldOfViewDegrees * .pi / 180 / 2)
        let aspect = canvas.width / max(1, canvas.height)
        let margin = max(padding, min(canvas.width, canvas.height) * 0.035)
        let usableX = max(0.2, 1 - 2 * margin / canvas.width)
        let usableZ = max(0.2, 1 - 2 * margin / canvas.height)

        let low = device.bounds.min, high = device.bounds.max
        var box: [SIMD3<Double>] = []
        for x in [low[0], high[0]] {
            for y in [low[1], high[1]] {
                for z in [low[2], high[2]] { box.append(SIMD3(x, y, z)) }
            }
        }

        var centerX = (low[0] + high[0]) / 2
        var centerZ = (low[2] + high[2]) / 2
        var distance = 1.0
        // Perspective makes the near parts look bigger, so aim and distance are settled together in a few rounds.
        for _ in 0..<4 {
            distance = box.map { p in
                max(abs(p.x - centerX) * focal / (aspect * usableX) - p.y, abs(p.z - centerZ) * focal / usableZ - p.y)
            }.max() ?? 1
            let xs = box.map { (($0.x - centerX) / ($0.y + distance)) }
            let zs = box.map { (($0.z - centerZ) / ($0.y + distance)) }
            let depth = distance + (low[1] + high[1]) / 2
            centerX += ((xs.min()! + xs.max()!) / 2) * depth
            centerZ += ((zs.min()! + zs.max()!) / 2) * depth
        }
        distance = box.map { p in
            max(abs(p.x - centerX) * focal / (aspect * usableX) - p.y, abs(p.z - centerZ) * focal / usableZ - p.y)
        }.max() ?? 1
        let screen = device.screen.corners.map { SIMD3($0[0], $0[1], $0[2]) }
        return MockupStage(canvas: canvas, focal: focal, centerX: centerX, centerZ: centerZ, distance: distance, corners: screen)
    }

    /// Canvas position (origin at the bottom left) of a point in the model's coordinates.
    public func project(_ point: SIMD3<Double>) -> CGPoint {
        let aspect = canvas.width / max(1, canvas.height)
        let depth = max(0.001, point.y + distance)
        let x = (point.x - centerX) * focal / depth / aspect
        let z = (point.z - centerZ) * focal / depth
        return CGPoint(x: (x + 1) / 2 * canvas.width, y: (z + 1) / 2 * canvas.height)
    }

    /// Roughly how many canvas pixels a metre of movement covers around the device.
    var pixelsPerMetre: Double { canvas.height * focal / (2 * distance) }

    /// How far the screen's corners are from its middle, in metres: how far the device's parts travel when it turns.
    var reach: Double {
        let middle = (corners[0] + corners[3]) / 2
        return corners.map { simd_length($0 - middle) }.max() ?? 0
    }

    /// Where a spot on the screen lands when the device is at rest. (0, 0) is the screen's bottom left.
    public func screenPoint(u: Double, v: Double) -> CGPoint {
        let bottom = corners[0] + (corners[1] - corners[0]) * u
        let top = corners[2] + (corners[3] - corners[2]) * u
        return project(bottom + (top - bottom) * v)
    }

    /// The box around the whole screen when the device is at rest.
    public var screenRect: CGRect {
        let points = corners.map(project)
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
}
