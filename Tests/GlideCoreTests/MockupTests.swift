import CoreGraphics
import simd
import CoreImage
import XCTest
@testable import GlideCore

/// The 3D devices built in Blender: what ships, how their motions behave, and that the video lands on their screens.
final class MockupTests: XCTestCase {
    private let library = MockupLibrary.shared

    private var devices: [MockupDevice] { library.entries.compactMap { library.device(id: $0.id) } }

    func testThereAreFourMacBooksAndFourIPhonesWithFourOrFiveMotionsEach() throws {
        try XCTSkipIf(MockupLibrary.shared.entries.isEmpty, "The devices have not been built; see the README.")
        XCTAssertEqual(library.entries(in: .macbook).count, 4)
        XCTAssertEqual(library.entries(in: .iphone).count, 4)
        XCTAssertEqual(devices.count, 8, "every device loads")
        for device in devices {
            XCTAssertEqual(device.motions.count, 6, device.id)
            XCTAssertNotNil(device.motion(id: "idle"), device.id)
        }
    }

    func testEveryDeviceHasItsModelSourceAndPicture() throws {
        for entry in library.entries {
            let model = try XCTUnwrap(library.modelURL(id: entry.id))
            let fileManager = FileManager.default
            XCTAssertTrue(fileManager.fileExists(atPath: model.path), entry.id)
            XCTAssertTrue(fileManager.fileExists(atPath: model.deletingLastPathComponent().appendingPathComponent("model.blend").path), entry.id)
            XCTAssertTrue(fileManager.fileExists(atPath: try XCTUnwrap(library.thumbnailURL(id: entry.id)).path), entry.id)
        }
    }

    func testEveryArrivalEndsAtTheRestingPose() throws {
        for device in devices {
            let rest = try XCTUnwrap(device.motion(id: "idle")).pose(at: 0)
            for motion in device.motions {
                let label = "\(device.id) \(motion.id)"
                let end = motion.pose(at: motion.settle)
                XCTAssertEqual(end.display, 1, accuracy: 0.001, label)
                XCTAssertEqual(end.lid, rest.lid, accuracy: 0.001, label)
                XCTAssertLessThan(simd_length(end.position - rest.position), 0.0005, label)
                // The same turn, whichever way round the quaternion happens to be written.
                XCTAssertGreaterThan(abs(simd_dot(end.rotation.vector, rest.rotation.vector)), 0.9999, label)
            }
        }
    }

    func testTheDriftNeverJumpsHoweverLongTheVideoRuns() {
        for device in devices {
            for motion in device.motions {
                let label = "\(device.id) \(motion.id)"
                XCTAssertGreaterThan(motion.duration - motion.settle, 10, label)
                // The same moment one drift cycle later.
                XCTAssertEqual(motion.pose(at: motion.settle + 2), motion.pose(at: motion.duration + 2), label)
                // Across the join where it wraps, and across where the arrival hands over to it.
                for joint in [motion.duration, motion.settle] {
                    let before = motion.pose(at: joint - 1.0 / 60), after = motion.pose(at: joint + 1.0 / 60)
                    XCTAssertLessThan(simd_length(after.position - before.position), 0.001, label)
                    XCTAssertGreaterThan(abs(simd_dot(after.rotation.vector, before.rotation.vector)), 0.9999, label)
                }
            }
        }
    }

    func testALaptopsDisplayWakesAsItsLidOpens() throws {
        for device in devices where device.family == .macbook {
            let motion = try XCTUnwrap(device.motion(id: "open-from-above"))
            XCTAssertEqual(motion.pose(at: 0).display, 0, device.id)
            XCTAssertEqual(motion.pose(at: motion.settle).display, 1, device.id)
        }
        for device in devices where device.family == .iphone {
            XCTAssertEqual(device.motions.first?.pose(at: 0).display, 1, device.id)
        }
    }

    func testMotionsStartWithTheDeviceInViewOrLeavingTheEdge() throws {
        // No fading in from nothing, and no long wait on an empty frame.
        for device in devices {
            let canvas = CGSize(width: 1600, height: 1000)
            let stage = MockupStage.fit(device, canvas: canvas, padding: 40)
            for motion in device.motions {
                let pose = motion.pose(at: 0.4)
                let center = stage.project(SIMD3(Double(pose.position.x), Double(pose.position.y), Double(pose.position.z)))
                XCTAssertTrue(CGRect(origin: .zero, size: canvas).insetBy(dx: -canvas.width * 0.5, dy: -canvas.height * 0.5).contains(center), "\(device.id) \(motion.id)")
            }
        }
    }

    func testADeviceAtRestFitsTheCanvas() {
        for device in devices {
            for canvas in [CGSize(width: 1600, height: 1000), CGSize(width: 1000, height: 1000), CGSize(width: 720, height: 1280)] {
                let stage = MockupStage.fit(device, canvas: canvas, padding: 40)
                for x in [device.bounds.min[0], device.bounds.max[0]] {
                    for y in [device.bounds.min[1], device.bounds.max[1]] {
                        for z in [device.bounds.min[2], device.bounds.max[2]] {
                            let point = stage.project(SIMD3(x, y, z))
                            XCTAssertTrue(CGRect(origin: .zero, size: canvas).insetBy(dx: -1, dy: -1).contains(point), "\(device.id) on \(canvas)")
                        }
                    }
                }
            }
        }
    }

    func testTheScreenIsTheRightWayUp() {
        for device in devices {
            let stage = MockupStage.fit(device, canvas: CGSize(width: 1600, height: 1000), padding: 40)
            XCTAssertGreaterThan(stage.screenPoint(u: 1, v: 0.5).x, stage.screenPoint(u: 0, v: 0.5).x, device.id)
            XCTAssertGreaterThan(stage.screenPoint(u: 0.5, v: 1).y, stage.screenPoint(u: 0.5, v: 0).y, device.id)
        }
    }

    func testOlderProjectsHaveNoDeviceAndAChoiceSurvivesSaving() throws {
        XCTAssertNil(try JSONDecoder().decode(RenderStyle.self, from: Data("{}".utf8)).mockup)
        var style = RenderStyle()
        style.mockup = MockupChoice(deviceID: "iphone-air", motionID: "rise")
        let saved = try JSONDecoder().decode(RenderStyle.self, from: JSONEncoder().encode(style))
        XCTAssertEqual(saved.mockup, style.mockup)
    }

    func testProjectsSavedWithTheOlderPhoneModelsStillOpen() throws {
        try XCTSkipIf(MockupLibrary.shared.entries.isEmpty, "The devices have not been built; see the README.")
        let old = try JSONDecoder().decode(MockupChoice.self, from: Data(#"{"deviceID":"iphone-17-pro","motionID":"rise"}"#.utf8))
        XCTAssertEqual(old, MockupChoice(deviceID: "iphone-18-pro", motionID: "rise"))
        XCTAssertNotNil(library.device(id: old.deviceID))
    }

    func testTheDeviceIsDrawnLargerThanTheCanvasWithinALimit() {
        XCTAssertEqual(MockupRenderer.supersampling(for: CGSize(width: 2560, height: 1600)), 2)
        XCTAssertEqual(MockupRenderer.supersampling(for: CGSize(width: 1280, height: 800)), 2)
        let large = CGSize(width: 3840, height: 3840)
        let scale = MockupRenderer.supersampling(for: large)
        XCTAssertGreaterThanOrEqual(scale, 1)
        XCTAssertLessThan(scale, 2)
        XCTAssertLessThanOrEqual(large.width * scale * large.height * scale, 26_500_001)
    }

    func testExportsGetEnoughBitsForFineDetail() {
        let canvas = CGSize(width: 2560, height: 1600)
        // About 44 Mbps for H.264 at 2560 x 1600 and 60 fps. Apple's preset gave this kind of video about 15 to 25.
        XCTAssertGreaterThan(Exporter.bitRate(canvas: canvas, fps: 60, codec: .h264), 40_000_000)
        XCTAssertLessThan(Exporter.bitRate(canvas: canvas, fps: 60, codec: .hevc), Exporter.bitRate(canvas: canvas, fps: 60, codec: .h264))
        XCTAssertEqual(Exporter.bitRate(canvas: canvas, fps: 30, codec: .h264) * 2, Exporter.bitRate(canvas: canvas, fps: 60, codec: .h264))
    }

    /// Each device draws in a renderer of its own, so this is also every renderer's first frame.
    func testThePictureLandsOnTheScreenFromTheFirstFrame() throws {
        let canvas = CGSize(width: 480, height: 360)
        let orange = try XCTUnwrap(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        orange.setFillColor(CGColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1))
        orange.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let picture = try XCTUnwrap(orange.makeImage())

        for device in devices {
            let still = try XCTUnwrap(MockupStudio.still(deviceID: device.id, canvas: canvas, padding: 12, screen: picture), device.id)
            let middle = MockupStage.fit(device, canvas: canvas, padding: 12).screenPoint(u: 0.5, v: 0.5)
            let center = try pixel(of: still, x: Int(middle.x), y: Int(canvas.height - middle.y))
            XCTAssertEqual(center.r, 255, accuracy: 6, device.id)
            XCTAssertEqual(center.g, 128, accuracy: 10, device.id)
            XCTAssertEqual(center.b, 0, accuracy: 6, device.id)
            XCTAssertEqual(try pixel(of: still, x: 2, y: 2).a, 0, device.id + ": transparent around the device")
        }
    }

    func testADeviceSitsOnPureWhiteAndTheOwnBackgroundComesBackWithoutIt() throws {
        var style = RenderStyle()
        style.background.kind = .wallpaper
        style.background.wallpaperID = "ember"
        XCTAssertEqual(style.activeBackground.kind, .wallpaper, "no device: the project's own background")

        style.mockup = MockupChoice(deviceID: "iphone-17", motionID: "idle")
        XCTAssertEqual(style.activeBackground, .white)
        XCTAssertEqual(style.activeBackground.solid, RGB(hex: 0xFFFFFF))

        style.activeBackground.kind = .gradient
        XCTAssertEqual(style.activeBackground.kind, .gradient, "another background can still be picked for the device")
        XCTAssertEqual(style.background.kind, .wallpaper, "without touching the project's own")

        style.mockup = nil
        XCTAssertEqual(style.activeBackground.wallpaperID, "ember")

        let saved = try JSONDecoder().decode(RenderStyle.self, from: JSONEncoder().encode(style))
        XCTAssertEqual(saved.mockupBackground?.kind, .gradient)
    }

    private func pixel(of image: CGImage, x: Int, y: Int) throws -> (r: Double, g: Double, b: Double, a: Double) {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return (Double(bytes[0]), Double(bytes[1]), Double(bytes[2]), Double(bytes[3]))
    }
}
