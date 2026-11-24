import CoreImage
import ImageIO
import XCTest
@testable import SoftcutCore

private func plainBundle(duration: Double = 10) -> RecordingBundle {
    let manifest = RecordingManifest(displayID: 0, displayWidth: 1600, displayHeight: 1000, pixelScale: 2, duration: duration,
                                     hasSystemAudio: false, hasMicrophone: false, keysCaptured: true)
    return RecordingBundle(folder: URL(fileURLWithPath: "/dev/null"), manifest: manifest, input: InputLog(), cursors: [])
}

final class CropTests: XCTestCase {
    func testClampingKeepsTheRectangleOnScreenAndNotTiny() {
        let rect = CropRect(x: 0.9, y: -0.2, width: 0.5, height: 0.01)
        XCTAssertGreaterThanOrEqual(rect.x, 0)
        XCTAssertLessThanOrEqual(rect.x + rect.width, 1 + 1e-9)
        XCTAssertGreaterThanOrEqual(rect.y, 0)
        XCTAssertGreaterThanOrEqual(rect.height, CropRect.minimumSize)
        XCTAssertTrue(CropRect.full.isFull)
        XCTAssertFalse(CropRect(x: 0.1, y: 0, width: 0.5, height: 1).isFull)
    }

    func testLayoutUsesTheShapeOfTheCroppedScreen() {
        var style = RenderStyle()
        style.crop = CropRect(x: 0, y: 0, width: 0.5, height: 1)   // a 800 x 1000 slice of a 1600 x 1000 screen
        let (_, content) = FrameRenderer.layout(displayWidth: 1600, displayHeight: 1000, style: style)
        XCTAssertEqual(content.width / content.height, 0.8, accuracy: 0.01)
    }

    func testCameraNeverShowsWhatWasCroppedAway() {
        var project = EditProject()
        project.settings.style.crop = CropRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        // A zoom aimed at the far corner of the whole screen, which is outside the crop.
        project.zooms = [ZoomSegment(start: 1, end: 6, focusX: 0.98, focusY: 0.02, focusTime: 1, scale: 2, follow: .fixed)]
        let plan = AutoEditor.makePlan(for: plainBundle(), project: project)

        // Unzoomed, the view is exactly the crop.
        let idle = plan.camera(at: 0.2)
        XCTAssertEqual(idle.centerX, 0.5, accuracy: 0.001)
        XCTAssertEqual(idle.centerY, 0.5, accuracy: 0.001)

        for step in 0..<100 {
            let state = plan.camera(at: Double(step) / 10)
            let halfWidth = 0.5 / (2 * state.scale), halfHeight = 0.5 / (2 * state.scale)
            XCTAssertGreaterThanOrEqual(state.centerX - halfWidth, 0.25 - 1e-9, "left edge at step \(step)")
            XCTAssertLessThanOrEqual(state.centerX + halfWidth, 0.75 + 1e-9, "right edge at step \(step)")
            XCTAssertGreaterThanOrEqual(state.centerY - halfHeight, 0.25 - 1e-9, "top edge at step \(step)")
            XCTAssertLessThanOrEqual(state.centerY + halfHeight, 0.75 + 1e-9, "bottom edge at step \(step)")
        }
    }
}

final class DeviceFrameTests: XCTestCase {
    func testEveryDeviceAndAspectFitsInsideThePaddingAndKeepsTheScreenShape() {
        for device in DeviceFrame.allCases {
            for aspect in AspectChoice.allCases {
                var style = RenderStyle()
                style.deviceFrame = device
                style.aspect = aspect
                let layout = FrameRenderer.fullLayout(displayWidth: 1728, displayHeight: 1117, style: style)
                let pad = style.padding * layout.canvas.width
                let name = "\(device)/\(aspect)"

                XCTAssertEqual(layout.content.width / layout.content.height, 1728.0 / 1117, accuracy: 0.01, name)
                // The whole device, shadow outline included, stays inside the padded area.
                let outer = layout.device.shadowRect
                XCTAssertGreaterThanOrEqual(outer.minX, pad - 3, name)
                XCTAssertLessThanOrEqual(outer.maxX, layout.canvas.width - pad + 3, name)
                XCTAssertGreaterThanOrEqual(outer.minY, pad - 3, name)
                XCTAssertLessThanOrEqual(outer.maxY, layout.canvas.height - pad + 3, name)
                // The picture and its clip are inside the outline.
                XCTAssertTrue(outer.insetBy(dx: -2, dy: -2).contains(layout.content), name)
                XCTAssertTrue(layout.device.maskRect.insetBy(dx: -2, dy: -2).contains(layout.content), name)
            }
        }
    }

    func testAutoAspectGrowsTheCanvasForADeviceWithAStand() {
        var plain = RenderStyle()
        plain.deviceFrame = .none
        var monitor = RenderStyle()
        monitor.deviceFrame = .monitor
        let a = FrameRenderer.fullLayout(displayWidth: 1600, displayHeight: 1000, style: plain)
        let b = FrameRenderer.fullLayout(displayWidth: 1600, displayHeight: 1000, style: monitor)
        XCTAssertGreaterThan(b.canvas.height, a.canvas.height, "a stand and chin need room under the screen")
    }

    func testDrawnFramesHaveArtButNoneDoesNot() {
        let canvas = CGSize(width: 800, height: 600)
        for device in DeviceFrame.allCases {
            let geometry = DeviceFrames.geometry(device, available: CGRect(x: 40, y: 40, width: 720, height: 520), screenAspect: 1.6,
                                                 cornerRadius: 12, canvasWidth: canvas.width)
            let art = DeviceFrames.art(device, geometry: geometry, canvas: canvas)
            XCTAssertEqual(art == nil, device == .none, "\(device)")
        }
    }
}

final class ProjectLookTests: XCTestCase {
    func testNewSettingsSurviveSaving() throws {
        var project = EditProject()
        project.settings.style.crop = CropRect(x: 0.1, y: 0.2, width: 0.6, height: 0.5)
        project.settings.style.deviceFrame = .laptop
        project.settings.style.cursorStyle = .ring
        project.settings.style.motionBlur = 0.8
        project.settings.style.background.kind = .wallpaper
        project.settings.style.background.wallpaperID = "ember"
        project.zooms = [ZoomSegment(start: 1, end: 3, focusX: 0.5, focusY: 0.5, focusTime: 1, instant: true)]
        project.slices = [TimeSegment(sourceStart: 0, sourceEnd: 5, hideCursor: true)]

        let decoded = try JSONDecoder().decode(EditProject.self, from: JSONEncoder().encode(project))
        XCTAssertEqual(decoded, project)
        XCTAssertTrue(decoded.zooms[0].instant)
        XCTAssertTrue(decoded.slices[0].hideCursor)
    }

    func testTimeMapFindsTheSliceAMomentIsIn() {
        let map = TimeMap(segments: [TimeSegment(sourceStart: 0, sourceEnd: 4, hideCursor: true), TimeSegment(sourceStart: 6, sourceEnd: 9)])
        XCTAssertEqual(map.segment(atSource: 2)?.hideCursor, true)
        XCTAssertEqual(map.segment(atSource: 7)?.hideCursor, false)
        XCTAssertNil(map.segment(atSource: 5))
    }

    func testAnInstantZoomArrivesMuchFasterThanAnEasedOne() {
        func scale(instant: Bool) -> Double {
            var project = EditProject()
            project.settings.zoomOnTyping = false
            project.zooms = [ZoomSegment(start: 2, end: 8, focusX: 0.5, focusY: 0.5, focusTime: 2, scale: 2, instant: instant)]
            // A tenth of a second in: the eased zoom has only just begun, the instant one is nearly there.
            return AutoEditor.makePlan(for: plainBundle(), project: project).camera(at: 2.1).scale
        }
        XCTAssertGreaterThan(scale(instant: true), 1.7)
        XCTAssertLessThan(scale(instant: false), 1.5)
    }
}

final class WallpaperAndCursorTests: XCTestCase {
    func testWallpapersAreUniqueAndFillTheCanvas() {
        XCTAssertEqual(Set(Wallpapers.all.map(\.id)).count, Wallpapers.all.count)
        XCTAssertGreaterThanOrEqual(Wallpapers.all.count, 12)
        let canvas = CGSize(width: 640, height: 400)
        for wallpaper in Wallpapers.all {
            let image = Wallpapers.image(wallpaper, canvas: canvas)
            XCTAssertEqual(image.extent.size, canvas, wallpaper.id)
            XCTAssertNotNil(Wallpapers.thumbnail(id: wallpaper.id, size: CGSize(width: 80, height: 50)), wallpaper.id)
        }
        XCTAssertEqual(Wallpapers.wallpaper(id: "no-such-wallpaper").id, Wallpapers.all[0].id, "an unknown id falls back to the first")
    }

    func testDrawnCursorsHaveAHotspotInsideTheirPicture() {
        XCTAssertNil(CursorArt.art(for: .system))
        XCTAssertNil(CursorArt.art(for: .dark))
        // Recorded and Dark use the recorded pictures; the rest are drawn in code.
        for style in CursorStyle.allCases where style != .system && style != .dark {
            let art = CursorArt.art(for: style)
            XCTAssertNotNil(art, "\(style)")
            guard let art else { continue }
            XCTAssertGreaterThan(art.pixelHeight, 0)
            XCTAssertTrue((0...art.meta.width).contains(art.meta.hotspotX), "\(style)")
            XCTAssertTrue((0...art.meta.height).contains(art.meta.hotspotY), "\(style)")
        }
    }
}

/// Renders real frames, which needs the video frameworks (so these run outside the sandbox).
@MainActor
final class RenderSmokeTests: XCTestCase {
    private var folder: URL!
    private var bundle: RecordingBundle!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("softcut-render-test-\(UUID().uuidString)")
        bundle = try DemoRecording.make(in: folder)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func pixelsVary(_ image: CGImage) -> Bool {
        // A frame that came out blank or a single color would fail this: sample a grid and look for differences.
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return false }
        let bytesPerPixel = image.bitsPerPixel / 8
        var seen = Set<[UInt8]>()
        for gx in 1..<8 {
            for gy in 1..<8 {
                let offset = (gy * image.height / 8) * image.bytesPerRow + (gx * image.width / 8) * bytesPerPixel
                seen.insert([bytes[offset], bytes[offset + 1], bytes[offset + 2]])
            }
        }
        return seen.count > 3
    }

    func testEveryDeviceCursorAndBackgroundRenders() async throws {
        var variants: [(String, (inout EditProject) -> Void)] = []
        for device in DeviceFrame.allCases { variants.append(("device \(device)", { $0.settings.style.deviceFrame = device })) }
        for cursor in CursorStyle.allCases { variants.append(("cursor \(cursor)", { $0.settings.style.cursorStyle = cursor })) }
        for kind in BackgroundKind.allCases { variants.append(("background \(kind)", { $0.settings.style.background.kind = kind })) }
        variants.append(("cropped", { $0.settings.style.crop = CropRect(x: 0.1, y: 0.1, width: 0.6, height: 0.6) }))
        variants.append(("vertical", { $0.settings.style.aspect = .vertical }))

        for (name, change) in variants {
            var project = EditProject.auto(for: bundle)
            change(&project)
            let session = try await PreviewSession.make(bundle: bundle, project: project, previewWidth: 640)
            let frame = try await session.frame(atOutputTime: 4.0)
            let expected = OutputGeometry.size(for: bundle, style: { var s = project.settings.style; s.maxOutputWidth = 640; return s }())
            XCTAssertEqual(CGFloat(frame.width), expected.width, accuracy: 1, name)
            XCTAssertEqual(CGFloat(frame.height), expected.height, accuracy: 1, name)
            XCTAssertTrue(pixelsVary(frame), "\(name) came out blank")
        }
    }

    func testChangingTheLookInPlaceKeepsTheSameSession() async throws {
        let project = EditProject.auto(for: bundle)
        let session = try await PreviewSession.make(bundle: bundle, project: project, previewWidth: 640)
        var changed = project
        changed.settings.style.background.kind = .wallpaper
        changed.settings.style.cursorScale = 2
        XCTAssertTrue(session.update(project: changed), "colors and sizes must apply without rebuilding")

        changed.settings.style.aspect = .square
        XCTAssertTrue(session.update(project: changed), "a different canvas shape applies in place too")
        XCTAssertEqual(session.canvasSize.width, session.canvasSize.height)
        let frame = try await session.frame(atOutputTime: 0.5)
        XCTAssertEqual(frame.width, frame.height, "and frames come out in the new shape")

        changed.settings.style.padding = 0.2
        XCTAssertTrue(session.update(project: changed), "so does padding")

        changed.slices[0].speed *= 2
        XCTAssertFalse(session.update(project: changed), "different clips need a new session")
    }

    func testGIFExportHasTheRightSizeAndFrameCount() async throws {
        let plan = AutoEditor.makePlan(for: bundle, project: EditProject.auto(for: bundle))
        let output = folder.appendingPathComponent("out.gif")
        try await Exporter.exportGIF(bundle: bundle, plan: plan, to: output, width: 320, fps: 6)

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        let expectedFrames = Int(plan.outputDuration * 6)
        XCTAssertEqual(CGImageSourceGetCount(source), expectedFrames, accuracy: 1)
        let first = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(first.width, 320)
    }
}

final class SVGWallpaperTests: XCTestCase {
    private final class Checker: NSObject, XMLParserDelegate {
        var root: String?
        var attributes: [String: String] = [:]
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes attributeDict: [String: String]) {
            if root == nil { root = name; attributes = attributeDict }
        }
    }

    func testEveryWallpaperIsValidSmallSVG() throws {
        var total = 0
        for wallpaper in Wallpapers.all {
            let text = Wallpapers.svg(wallpaper, size: CGSize(width: 1600, height: 1000))
            let data = Data(text.utf8)
            total += data.count

            let checker = Checker()
            let parser = XMLParser(data: data)
            parser.delegate = checker
            XCTAssertTrue(parser.parse(), "\(wallpaper.id) is not well-formed: \(parser.parserError?.localizedDescription ?? "")")
            XCTAssertEqual(checker.root, "svg", wallpaper.id)
            XCTAssertEqual(checker.attributes["width"], "1600")
            XCTAssertEqual(checker.attributes["viewBox"], "0 0 1600 1000")
            XCTAssertLessThan(data.count, 1_500, "\(wallpaper.id) should be about a kilobyte of text")
            XCTAssertEqual(text.components(separatedBy: "<radialGradient").count - 1, wallpaper.glows.count)
        }
        XCTAssertLessThan(total, 16_000, "all of the wallpapers together are a few kilobytes, not megabytes")
    }

    func testDrawnAtTheRequestedSizeWhateverTheSize() throws {
        let context = CIContext()
        for size in [CGSize(width: 160, height: 100), CGSize(width: 1280, height: 868), CGSize(width: 3840, height: 2160)] {
            let image = Wallpapers.image(Wallpapers.wallpaper(id: "nebula"), canvas: size)
            XCTAssertEqual(image.extent.size, size)
            let rendered = try XCTUnwrap(context.createCGImage(image, from: image.extent))
            XCTAssertEqual(CGFloat(rendered.width), size.width)
        }
    }

    func testTheSVGIsActuallyDrawnNotJustTheBaseColor() throws {
        // Nebula has a bright violet glow in the top-left and none in the middle of the right edge.
        let size = CGSize(width: 800, height: 500)
        let wallpaper = Wallpapers.wallpaper(id: "nebula")
        let image = try XCTUnwrap(SVGRaster.cgImage(svg: Data(Wallpapers.svg(wallpaper, size: size).utf8), size: size))
        func pixel(_ x: Double, _ y: Double) -> (r: Int, g: Int, b: Int) {
            let data = CFDataGetBytePtr(image.dataProvider!.data!)!
            let offset = Int(y * Double(image.height)) * image.bytesPerRow + Int(x * Double(image.width)) * (image.bitsPerPixel / 8)
            return (Int(data[offset]), Int(data[offset + 1]), Int(data[offset + 2]))
        }
        let glow = pixel(0.2, 0.2)     // the center of the first glow
        let base = RGB(hex: 0x1B1038)
        XCTAssertGreaterThan(glow.b, 150, "blue-violet at the glow: \(glow)")
        XCTAssertGreaterThan(Double(glow.r) / 255, base.r + 0.15, "much brighter than the base color")
    }

    func testAnSVGFileCanBeUsedAsTheBackground() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("softcut-svgbg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("mine.svg")
        try Data("<svg xmlns='http://www.w3.org/2000/svg' width='100' height='60' viewBox='0 0 100 60'><rect width='100' height='60' fill='#FF0000'/><rect width='50' height='60' fill='#0000FF'/></svg>".utf8).write(to: file)

        let drawn = try XCTUnwrap(SVGRaster.cgImage(svgFile: file, size: CGSize(width: 400, height: 240)))
        XCTAssertEqual(drawn.width, 400)
        XCTAssertNil(SVGRaster.cgImage(svgFile: folder.appendingPathComponent("photo.png"), size: CGSize(width: 10, height: 10)), "only .svg files are drawn this way")
    }
}

final class DarkCursorTests: XCTestCase {
    /// A square cursor on a transparent margin: `inside` filling it, `outline` as a border around it.
    private func square(inside: CGFloat, outline: CGFloat, size: Int = 48) -> CGImage {
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: outline, alpha: 1))
        ctx.fill(CGRect(x: 8, y: 8, width: size - 16, height: size - 16))
        ctx.setFillColor(CGColor(gray: inside, alpha: 1))
        ctx.fill(CGRect(x: 11, y: 11, width: size - 22, height: size - 22))
        return ctx.makeImage()!
    }

    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (gray: Int, alpha: Int) {
        let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let offset = y * ctx.bytesPerRow + x * 4
        return (Int(data[offset]), Int(data[offset + 3]))
    }

    func testALightCursorIsRecognisedAndMadeDark() {
        let light = square(inside: 1, outline: 0)      // white with a black outline, as macOS draws it over a dark screen
        XCTAssertTrue(CursorArt.isLight(light))

        let dark = CursorArt.darkened(light)
        XCTAssertEqual(dark.width, light.width)
        XCTAssertLessThan(pixel(dark, 24, 24).gray, 20, "the inside is now black")
        XCTAssertGreaterThan(pixel(dark, 9, 24).gray, 235, "the outline is now white")
        XCTAssertEqual(pixel(dark, 2, 2).alpha, 0, "transparent stays transparent")
        XCTAssertEqual(pixel(dark, 24, 24).alpha, 255)
        XCTAssertFalse(CursorArt.isLight(dark))
    }

    func testADarkCursorIsLeftAlone() {
        let dark = square(inside: 0, outline: 1)       // black with a white outline, the usual cursor
        XCTAssertFalse(CursorArt.isLight(dark))
        let same = CursorArt.darkened(dark)
        XCTAssertEqual(pixel(same, 24, 24).gray, pixel(dark, 24, 24).gray)
        XCTAssertEqual(pixel(same, 9, 24).gray, pixel(dark, 9, 24).gray)
    }

    func testAThinCursorLikeATextCaretIsJudgedByItsSolidPixels() {
        // Two pixels wide: there is hardly any "inside", but it is clearly white.
        let ctx = CGContext(data: nil, width: 24, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 11, y: 4, width: 2, height: 40))
        let caret = ctx.makeImage()!
        XCTAssertTrue(CursorArt.isLight(caret))
        XCTAssertLessThan(pixel(CursorArt.darkened(caret), 12, 24).gray, 20)
    }

    func testDarkIsTheDefaultAndSavedChoicesAreKept() throws {
        XCTAssertEqual(RenderStyle().cursorStyle, .dark)
        let saved = try JSONDecoder().decode(RenderStyle.self, from: Data(#"{"cursorStyle":"system"}"#.utf8))
        XCTAssertEqual(saved.cursorStyle, .system, "a project that chose the recorded cursor keeps it")
        let older = try JSONDecoder().decode(RenderStyle.self, from: Data(#"{"padding":0.1}"#.utf8))
        XCTAssertEqual(older.cursorStyle, .dark, "a project that never chose one gets the new default")
    }

    func testTheDrawnArrowIsBlackWithAWhiteOutline() throws {
        let art = try XCTUnwrap(CursorArt.art(for: .arrow))
        let image = try XCTUnwrap(CIContext().createCGImage(art.image, from: art.image.extent))
        XCTAssertFalse(CursorArt.isLight(image))
    }
}
