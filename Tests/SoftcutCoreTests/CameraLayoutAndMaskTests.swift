import CoreGraphics
import XCTest
@testable import SoftcutCore

final class CameraLayoutGeometryTests: XCTestCase {
    private func layout(_ choice: CameraLayout, aspect: AspectChoice = .auto, hasCamera: Bool = true, share: Double = 0.34,
                        device: DeviceFrame = .none) -> FrameRenderer.Layout {
        var style = RenderStyle()
        style.cameraLayout = choice
        style.aspect = aspect
        style.splitRatio = share
        style.deviceFrame = device
        return FrameRenderer.fullLayout(displayWidth: 1728, displayHeight: 1117, style: style, hasCamera: hasCamera)
    }

    func testOnlySplitLayoutsWithAWebcamGetAPanel() {
        XCTAssertNil(layout(.bubble).camera)
        XCTAssertNil(layout(.cutout).camera)
        XCTAssertNil(layout(.splitRight, hasCamera: false).camera, "no webcam, so the screen keeps the whole canvas")
        for choice in [CameraLayout.splitRight, .splitLeft, .splitTop, .splitBottom] {
            XCTAssertNotNil(layout(choice).camera, "\(choice)")
        }
    }

    func testAnUnusedPanelLeavesTheLayoutExactlyAsItWas() {
        let plain = layout(.bubble)
        let withoutWebcam = layout(.splitRight, hasCamera: false)
        XCTAssertEqual(plain.canvas, withoutWebcam.canvas)
        XCTAssertEqual(plain.content, withoutWebcam.content)
    }

    func testSideBySidePanelsDoNotOverlapAndStayOnTheCanvas() {
        for choice in [CameraLayout.splitRight, .splitLeft] {
            for aspect in [AspectChoice.auto, .wide, .square, .vertical] {
                let result = layout(choice, aspect: aspect)
                let camera = try! XCTUnwrap(result.camera)
                let name = "\(choice)/\(aspect)"
                XCTAssertFalse(camera.intersects(result.device.shadowRect), name)
                XCTAssertGreaterThanOrEqual(camera.minX, 0, name)
                XCTAssertLessThanOrEqual(camera.maxX, result.canvas.width, name)
                XCTAssertGreaterThanOrEqual(camera.minY, 0, name)
                XCTAssertLessThanOrEqual(camera.maxY, result.canvas.height, name)
                // The screen keeps its own shape however it is squeezed.
                XCTAssertEqual(result.content.width / result.content.height, 1728.0 / 1117, accuracy: 0.01, name)
                if choice == .splitRight { XCTAssertGreaterThan(camera.minX, result.device.shadowRect.maxX, name) }
                else { XCTAssertLessThan(camera.maxX, result.device.shadowRect.minX, name) }
            }
        }
    }

    func testStackedPanelsDoNotOverlapAndStayOnTheCanvas() {
        for choice in [CameraLayout.splitTop, .splitBottom] {
            for aspect in [AspectChoice.auto, .wide, .square, .vertical] {
                let result = layout(choice, aspect: aspect)
                let camera = try! XCTUnwrap(result.camera)
                let name = "\(choice)/\(aspect)"
                XCTAssertFalse(camera.intersects(result.device.shadowRect), name)
                XCTAssertGreaterThanOrEqual(camera.minX, 0, name)
                XCTAssertLessThanOrEqual(camera.maxX, result.canvas.width, name)
                XCTAssertGreaterThanOrEqual(camera.minY, 0, name)
                XCTAssertLessThanOrEqual(camera.maxY, result.canvas.height, name)
                XCTAssertEqual(result.content.width / result.content.height, 1728.0 / 1117, accuracy: 0.01, name)
                // Canvas y grows upward: "above" is a larger y.
                if choice == .splitTop { XCTAssertGreaterThan(camera.minY, result.device.shadowRect.maxY - 1, name) }
                else { XCTAssertLessThan(camera.maxY, result.device.shadowRect.minY + 1, name) }
            }
        }
    }

    func testTheCameraShareMakesThePanelBigger() {
        let small = try! XCTUnwrap(layout(.splitRight, aspect: .wide, share: 0.2).camera)
        let large = try! XCTUnwrap(layout(.splitRight, aspect: .wide, share: 0.5).camera)
        XCTAssertGreaterThan(large.width, small.width * 1.8)
    }

    func testTheCanvasWidthNeverDependsOnTheLayout() {
        let widths = Set(CameraLayout.allCases.map { layout($0).canvas.width })
        XCTAssertEqual(widths.count, 1)
    }

    func testThePanelIsOnlyUsedWhenTheWebcamIsShownAndExists() {
        var style = RenderStyle()
        style.cameraLayout = .splitRight
        XCTAssertTrue(FrameRenderer.usesCameraPanel(style, hasWebcam: true))
        XCTAssertFalse(FrameRenderer.usesCameraPanel(style, hasWebcam: false))
        style.showWebcam = false
        XCTAssertFalse(FrameRenderer.usesCameraPanel(style, hasWebcam: true))
        style.showWebcam = true
        style.cameraLayout = .cutout
        XCTAssertFalse(FrameRenderer.usesCameraPanel(style, hasWebcam: true))
    }

    func testOldProjectsWithoutALayoutStillOpenAsBubbles() throws {
        let decoded = try JSONDecoder().decode(RenderStyle.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded.cameraLayout, .bubble)
        XCTAssertEqual(decoded.splitRatio, RenderStyle().splitRatio)
    }
}

/// Renders real frames, which needs the video frameworks (so these run outside the sandbox).
@MainActor
final class CameraLayoutAndMaskRenderTests: XCTestCase {
    private var folder: URL!
    private var bundle: RecordingBundle!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("softcut-layout-test-\(UUID().uuidString)")
        bundle = try DemoRecording.make(in: folder)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Plain output with no zooms, so two frames differ only because of what a test changed.
    private func quietProject(_ change: (inout EditProject) -> Void = { _ in }) -> EditProject {
        var project = EditProject.auto(for: bundle)
        project.zooms = []
        project.settings.style.motionBlur = 0
        project.settings.style.cursorScale = 0.01
        project.settings.style.background.kind = .solid
        change(&project)
        return project
    }

    private func frame(_ project: EditProject, at time: Double = 4) async throws -> Pixels {
        let session = try await PreviewSession.make(bundle: bundle, project: project, previewWidth: 800)
        return Pixels(try await session.frame(atOutputTime: time))
    }

    /// A frame's pixels, readable by position (0...1 from the top-left).
    struct Pixels {
        let width: Int, height: Int
        private let bytes: [UInt8]

        init(_ image: CGImage) {
            let w = image.width, h = image.height
            var data = [UInt8](repeating: 0, count: w * h * 4)
            data.withUnsafeMutableBytes { buffer in
                let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
            width = w
            height = h
            bytes = data
        }

        func color(_ x: Double, _ y: Double) -> (r: Int, g: Int, b: Int) {
            let px = min(width - 1, max(0, Int(x * Double(width)))), py = min(height - 1, max(0, Int(y * Double(height))))
            let offset = (py * width + px) * 4
            return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
        }

        /// The average difference per channel (0...255) between two frames of the same size over a region.
        func difference(from other: Pixels, in region: CGRect) -> Double {
            precondition(width == other.width && height == other.height)
            var total = 0, count = 0
            for gy in 0..<24 {
                for gx in 0..<24 {
                    let a = color(Double(region.minX + region.width * (Double(gx) + 0.5) / 24), Double(region.minY + region.height * (Double(gy) + 0.5) / 24))
                    let b = other.color(Double(region.minX + region.width * (Double(gx) + 0.5) / 24), Double(region.minY + region.height * (Double(gy) + 0.5) / 24))
                    total += abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b)
                    count += 3
                }
            }
            return Double(total) / Double(count)
        }
    }

    private let whole = CGRect(x: 0, y: 0, width: 1, height: 1)

    func testAFillRegionCoversItsPartOfTheScreenAndNothingElse() async throws {
        let baseline = try await frame(quietProject())
        let covered = try await frame(quietProject {
            $0.masks = [MaskRegion(start: 0, end: 20, rect: CropRect(x: 0, y: 0, width: 0.5, height: 1), kind: .fill)]
        })
        // Over the left half of the screen the picture changed a lot, and the right half is untouched.
        XCTAssertGreaterThan(covered.difference(from: baseline, in: CGRect(x: 0.2, y: 0.3, width: 0.2, height: 0.4)), 8)
        XCTAssertLessThan(covered.difference(from: baseline, in: CGRect(x: 0.62, y: 0.3, width: 0.25, height: 0.4)), 1.5)
    }

    func testBlurAndPixelateChangeTheirRegion() async throws {
        let baseline = try await frame(quietProject())
        for kind in [MaskKind.blur, .pixelate] {
            let hidden = try await frame(quietProject {
                $0.masks = [MaskRegion(start: 0, end: 20, rect: CropRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8), kind: kind, strength: 1)]
            })
            XCTAssertGreaterThan(hidden.difference(from: baseline, in: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)), 1, "\(kind)")
        }
    }

    func testARegionOnlyHidesDuringItsTime() async throws {
        let baseline = try await frame(quietProject(), at: 4)
        let outside = try await frame(quietProject {
            $0.masks = [MaskRegion(start: 6, end: 8, rect: CropRect(x: 0, y: 0, width: 1, height: 1), kind: .fill)]
        }, at: 4)
        XCTAssertLessThan(outside.difference(from: baseline, in: whole), 0.5)

        let disabled = try await frame(quietProject {
            $0.masks = [MaskRegion(start: 0, end: 20, rect: CropRect(x: 0, y: 0, width: 1, height: 1), kind: .fill, isDisabled: true)]
        }, at: 4)
        XCTAssertLessThan(disabled.difference(from: baseline, in: whole), 0.5)
    }

    func testARegionStaysOnTheSamePartOfTheScreenWhenTheCameraZoomsIn() async throws {
        // Zoomed in on the right half, a region over the left half is out of sight, so the picture is unchanged.
        let zoomed = quietProject {
            $0.zooms = [ZoomSegment(start: 1, end: 9, focusX: 0.85, focusY: 0.5, focusTime: 1, scale: 2, follow: .fixed)]
        }
        let baseline = try await frame(zoomed, at: 5)
        var withMask = zoomed
        withMask.masks = [MaskRegion(start: 0, end: 20, rect: CropRect(x: 0, y: 0, width: 0.3, height: 1), kind: .fill)]
        let masked = try await frame(withMask, at: 5)
        XCTAssertLessThan(masked.difference(from: baseline, in: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)), 1.5)
    }

    func testTheMagnifierDrawsALensThatTheCameraZoomDoesNot() async throws {
        let lens = ZoomSegment(start: 1, end: 9, focusX: 0.5, focusY: 0.5, focusTime: 1, scale: 2.5, follow: .fixed, presentation: .loupe)
        let baseline = try await frame(quietProject(), at: 5)
        let magnified = try await frame(quietProject { $0.zooms = [lens] }, at: 5)
        // The screen is not zoomed (the edges are the same), but something new is drawn on it.
        XCTAssertLessThan(magnified.difference(from: baseline, in: CGRect(x: 0.04, y: 0.04, width: 0.1, height: 0.1)), 1.5)
        XCTAssertGreaterThan(magnified.difference(from: baseline, in: whole), 0.4)

        // Outside its time there is no lens.
        let before = try await frame(quietProject { $0.zooms = [lens] }, at: 0.2)
        let reference = try await frame(quietProject(), at: 0.2)
        XCTAssertLessThan(before.difference(from: reference, in: whole), 0.5)
    }

    func testEverySplitLayoutPutsTheCameraInItsPanel() async throws {
        for choice in [CameraLayout.splitRight, .splitLeft, .splitTop, .splitBottom] {
            let project = quietProject { $0.settings.style.cameraLayout = choice }
            XCTAssertTrue(bundle.webcamURL != nil)
            let session = try await PreviewSession.make(bundle: bundle, project: project, previewWidth: 800)
            let image = try await session.frame(atOutputTime: 4)
            let style = { var s = project.settings.style; s.maxOutputWidth = 800; return s }()
            let layout = FrameRenderer.fullLayout(displayWidth: bundle.manifest.displayWidth, displayHeight: bundle.manifest.displayHeight,
                                                  style: style, hasCamera: true)
            let panel = try XCTUnwrap(layout.camera, "\(choice)")
            XCTAssertEqual(CGFloat(image.width), layout.canvas.width, accuracy: 1, "\(choice)")
            XCTAssertEqual(CGFloat(image.height), layout.canvas.height, accuracy: 1, "\(choice)")

            // The solid background is plain, so the panel's middle being different from the corner means the camera is there.
            let pixels = Pixels(image)
            let middle = pixels.color(Double(panel.midX / layout.canvas.width), 1 - Double(panel.midY / layout.canvas.height))
            let corner = pixels.color(0.004, 0.004)
            let spread = abs(middle.r - corner.r) + abs(middle.g - corner.g) + abs(middle.b - corner.b)
            XCTAssertGreaterThan(spread, 12, "\(choice): the camera's panel looks empty")
        }
    }

    func testChangingCameraLayoutAppliesInPlaceEvenWhenTheCanvasChanges() async throws {
        let project = quietProject()
        let session = try await PreviewSession.make(bundle: bundle, project: project, previewWidth: 640)
        var cutout = project
        cutout.settings.style.cameraLayout = .cutout
        XCTAssertTrue(session.update(project: cutout), "a cut-out sits on the same canvas, so it applies in place")

        var split = project
        split.settings.style.cameraLayout = .splitRight
        let before = session.canvasSize
        XCTAssertTrue(session.update(project: split), "a panel changes the canvas shape, which also applies in place")
        XCTAssertNotEqual(session.canvasSize, before)
    }

    func testCutoutRendersWithAPersonOrFallsBackToABubble() async throws {
        // The demo's cartoon face is not a person, so segmentation may find nothing; either way a frame must come out.
        let project = quietProject { $0.settings.style.cameraLayout = .cutout }
        let pixels = try await frame(project, at: 4)
        XCTAssertGreaterThan(pixels.width, 0)
    }
}

/// Motion blur must soften a camera move, never smear the picture beyond reading.
@MainActor
final class MotionBlurStrengthTests: XCTestCase {
    func testAZoomInStaysReadableWithFullMotionBlur() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("softcut-blur-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let bundle = try DemoRecording.make(in: folder)

        func frame(blur: Double, at time: Double) async throws -> CameraLayoutAndMaskRenderTests.Pixels {
            var project = EditProject.auto(for: bundle)
            project.settings.style.motionBlur = blur
            project.settings.style.showWebcam = false
            let session = try await PreviewSession.make(bundle: bundle, project: project, previewWidth: 800)
            return CameraLayoutAndMaskRenderTests.Pixels(try await session.frame(atOutputTime: time))
        }
        // Detail left in a frame: how much neighbouring pixels differ across the middle of it.
        func detail(_ pixels: CameraLayoutAndMaskRenderTests.Pixels) -> Double {
            var total = 0
            let step = 1.0 / Double(pixels.width)
            for gy in 0..<60 {
                for gx in 0..<200 {
                    let x = 0.15 + 0.7 * Double(gx) / 200, y = 0.2 + 0.6 * Double(gy) / 60
                    let a = pixels.color(x, y), b = pixels.color(x + step, y)
                    total += abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b)
                }
            }
            return Double(total)
        }

        let zoom = try XCTUnwrap(EditProject.auto(for: bundle).zooms.first)
        // In the middle of zooming in, when the camera moves fastest.
        let moment = zoom.start + 0.1
        let sharp = detail(try await frame(blur: 0, at: moment))
        let blurred = detail(try await frame(blur: 1, at: moment))
        XCTAssertLessThan(blurred, sharp, "the move is softened")
        XCTAssertGreaterThan(blurred, sharp * 0.45, "but the picture keeps most of its detail")
    }
}
