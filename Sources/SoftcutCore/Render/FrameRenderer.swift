import AVFoundation
import CoreImage
import simd
import CoreImage.CIFilterBuiltins
import AppKit
import ImageIO
import Vision

/// Draws one finished output frame from one screen frame: background, device, the screen cropped
/// and moved by the camera, cursor, click effects, webcam and rounded corners.
///
/// The plan can be swapped while frames are being drawn (the editor does this as sliders move),
/// so everything that depends on it lives in a `Look` that is replaced as a whole.
final class FrameRenderer: @unchecked Sendable {
    struct Sprite {
        let image: CIImage
        let meta: CursorImage
        let pixelHeight: Double
    }

    /// The parts of a frame that depend on the plan. Built once per plan, read for every frame.
    struct Look {
        var plan: EditPlan
        var canvasSize: CGSize
        var contentRect: CGRect
        var backdrop: CIImage
        var mask: CIImage
        /// Where the camera's own panel goes in a split layout, and its rounded shape.
        var cameraRect: CGRect?
        var cameraMask: CIImage
        /// The cursor drawn in code, when the style is not "recorded".
        var styleCursor: Sprite?
        /// The 3D device the video is shown inside, if any.
        var mockup: MockupLook?
    }

    /// What drawing a video inside a device needs: the device, its motion, where the camera stands, and the size to
    /// draw the flat picture of the screen at.
    struct MockupLook {
        let device: MockupDevice
        let motion: MockupMotion
        let stage: MockupStage
        let pictureSize: CGSize
        let renderer: MockupRenderer
    }

    /// Where everything goes for a style and a display.
    struct Layout {
        var canvas: CGSize
        var content: CGRect
        var device: DeviceGeometry
        /// The camera's panel in a split layout.
        var camera: CGRect?
    }

    /// What the renderer needs from each recording besides its plan: the cursor pictures and the size of its screen.
    struct SourceAssets {
        let sprites: [String: Sprite]
        /// The same cursors recolored dark, for the Dark style.
        let darkSprites: [String: Sprite]
        let cursorChanges: [CursorChange]
        let displayWidth: Double
        let displayHeight: Double
        /// Pixels per point on the display it was recorded from.
        let pixelScale: Double
    }

    private let assets: [UUID?: SourceAssets]
    /// Whether any recording has a webcam, which decides whether a split layout reserves room for it.
    private let hasWebcam: Bool
    private let bundleFolder: URL
    private let context: CIContext
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let lock = NSLock()
    private var captionCache: [String: (image: CIImage, size: CGSize)] = [:]
    private let captionLock = NSLock()
    private var look: Look
    /// The look before the canvas last changed size, for frames that were already on their way at the old size.
    private var previousLook: Look?
    private let metal: MTLDevice?
    private let metalQueue: MTLCommandQueue?
    private var mockupRenderers: [String: MockupRenderer] = [:]
    /// Drawing a preview, which has to keep up with playback and appears smaller than an export. Set before the first frame.
    var isPreview = false

    var canvasSize: CGSize { current.canvasSize }
    var contentRect: CGRect { current.contentRect }
    var plan: EditPlan { current.plan }

    private var current: Look {
        lock.lock()
        defer { lock.unlock() }
        return look
    }

    // MARK: Layout

    /// Canvas and screen placement for a display of the given size. The screen keeps its shape and sits
    /// inside an even padding; with Auto aspect the canvas takes the shape of the screen plus padding.
    static func layout(displayWidth: Double, displayHeight: Double, style: RenderStyle, hasCamera: Bool = false) -> (canvas: CGSize, content: CGRect) {
        let full = fullLayout(displayWidth: displayWidth, displayHeight: displayHeight, style: style, hasCamera: hasCamera)
        return (full.canvas, full.content)
    }

    /// Whether the style puts the camera in a panel of its own, which needs the webcam to be shown and to exist.
    static func usesCameraPanel(_ style: RenderStyle, hasWebcam: Bool) -> Bool {
        hasWebcam && style.showWebcam && style.cameraLayout.isSplit && mockupDevice(style) == nil
    }

    /// The device a style shows the video inside, if there is one and it can be found.
    static func mockupDevice(_ style: RenderStyle) -> MockupDevice? {
        style.mockup.flatMap { MockupLibrary.shared.device(id: $0.deviceID) }
    }

    static func fullLayout(displayWidth: Double, displayHeight: Double, style: RenderStyle, hasCamera: Bool = false) -> Layout {
        func even(_ value: Double) -> Double { (value / 2).rounded() * 2 }
        // Only the cropped part of the screen is shown, so its shape is what matters.
        let shownWidth = displayWidth * style.crop.width
        let shownHeight = displayHeight * style.crop.height
        let screenAspect = shownWidth / shownHeight

        let canvasWidth = even(Double(style.maxOutputWidth))
        let pad = even(style.padding * canvasWidth)
        let radius = style.cornerRadius * canvasWidth
        let fullWidth = max(2, canvasWidth - 2 * pad)

        // Inside a device, the screen goes wherever the device's screen ends up when it comes to rest.
        if let mockup = mockupDevice(style) {
            let canvas = CGSize(width: canvasWidth, height: even(canvasWidth / (style.aspect.ratio ?? mockup.family.automaticAspect)))
            let rect = MockupStage.fit(mockup, canvas: canvas, padding: pad).screenRect
            let device = DeviceGeometry(content: rect, maskRect: rect, maskRadius: 0, shadowRect: rect, shadowRadius: 0)
            return Layout(canvas: canvas, content: rect, device: device, camera: nil)
        }

        func geometry(in area: CGRect) -> DeviceGeometry {
            DeviceFrames.geometry(style.deviceFrame, available: area, screenAspect: screenAspect, cornerRadius: radius, canvasWidth: canvasWidth)
        }
        func tallDevice(width: Double) -> DeviceGeometry { geometry(in: CGRect(x: pad, y: 0, width: max(2, width), height: 100_000)) }

        guard hasCamera, style.cameraLayout.isSplit else {
            let canvasHeight: Double
            if let ratio = style.aspect.ratio {
                canvasHeight = even(canvasWidth / ratio)
            } else {
                // Auto: as tall as the device needs, plus the padding.
                canvasHeight = even(tallDevice(width: fullWidth).shadowRect.height + 2 * pad)
            }
            let available = CGRect(x: pad, y: pad, width: fullWidth, height: max(2, canvasHeight - 2 * pad))
            let device = geometry(in: available)
            return Layout(canvas: CGSize(width: canvasWidth, height: canvasHeight), content: device.content, device: device, camera: nil)
        }

        // The screen and the camera side by side, or one above the other.
        let gap = even(max(pad * 0.7, canvasWidth * 0.012))
        let share = min(max(style.splitRatio, 0.15), 0.6)
        switch style.cameraLayout {
        case .splitLeft, .splitRight:
            let cameraWidth = even(fullWidth * share)
            let screenWidth = fullWidth - cameraWidth - gap
            let canvasHeight = style.aspect.ratio.map { even(canvasWidth / $0) } ?? even(tallDevice(width: screenWidth).shadowRect.height + 2 * pad)
            let cameraOnRight = style.cameraLayout == .splitRight
            let screenArea = CGRect(x: cameraOnRight ? pad : pad + cameraWidth + gap, y: pad, width: screenWidth, height: max(2, canvasHeight - 2 * pad))
            let device = geometry(in: screenArea)
            let camera = CGRect(x: cameraOnRight ? pad + screenWidth + gap : pad, y: device.shadowRect.minY,
                                width: cameraWidth, height: device.shadowRect.height)
            return Layout(canvas: CGSize(width: canvasWidth, height: canvasHeight), content: device.content, device: device, camera: camera)

        default:
            let canvasHeight: Double
            let cameraHeight: Double
            let screenHeight: Double
            if let ratio = style.aspect.ratio {
                canvasHeight = even(canvasWidth / ratio)
                let available = max(4, canvasHeight - 2 * pad - gap)
                cameraHeight = even(available * share)
                screenHeight = available - cameraHeight
            } else {
                screenHeight = tallDevice(width: fullWidth).shadowRect.height
                cameraHeight = even(screenHeight * share / (1 - share))
                canvasHeight = even(screenHeight + gap + cameraHeight + 2 * pad)
            }
            let cameraBelow = style.cameraLayout == .splitBottom
            let screenArea = CGRect(x: pad, y: cameraBelow ? pad + cameraHeight + gap : pad, width: fullWidth, height: max(2, screenHeight))
            let device = geometry(in: screenArea)
            let camera = CGRect(x: device.shadowRect.minX, y: cameraBelow ? pad : pad + screenHeight + gap,
                                width: device.shadowRect.width, height: cameraHeight)
            return Layout(canvas: CGSize(width: canvasWidth, height: canvasHeight), content: device.content, device: device, camera: camera)
        }
    }

    // MARK: Setup

    init(sources: SourceSet, plan: EditPlan) {
        bundleFolder = sources.primary.folder

        let options: [CIContextOption: Any] = [
            .workingColorSpace: colorSpace,
            .outputColorSpace: colorSpace,
            .cacheIntermediates: false,
        ]
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: options)
            metal = device
            metalQueue = device.makeCommandQueue()
        } else {
            context = CIContext(options: options)
            metal = nil
            metalQueue = nil
        }

        func loadAssets(_ bundle: RecordingBundle) -> SourceAssets {
            var sprites: [String: Sprite] = [:]
            var darkSprites: [String: Sprite] = [:]
            for meta in bundle.cursors {
                let url = bundle.cursorsFolder.appendingPathComponent(meta.file)
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
                sprites[meta.id] = Sprite(image: CIImage(cgImage: image), meta: meta, pixelHeight: Double(image.height))
                darkSprites[meta.id] = Sprite(image: CIImage(cgImage: CursorArt.darkened(image)), meta: meta, pixelHeight: Double(image.height))
            }
            return SourceAssets(sprites: sprites, darkSprites: darkSprites, cursorChanges: bundle.input.cursors.sorted { $0.t < $1.t },
                                displayWidth: bundle.manifest.displayWidth, displayHeight: bundle.manifest.displayHeight,
                                pixelScale: Double(bundle.manifest.pixelScale))
        }
        var all: [UUID?: SourceAssets] = [nil: loadAssets(sources.primary)]
        for (id, bundle) in sources.attached { all[id] = loadAssets(bundle) }
        assets = all
        hasWebcam = sources.hasWebcam

        look = Look(plan: plan, canvasSize: .zero, contentRect: .zero, backdrop: .empty(), mask: .empty(), cameraRect: nil, cameraMask: .empty(), styleCursor: nil, mockup: nil)
        look = makeLook(plan: plan)
    }

    /// Switches to a new plan.
    func update(plan: EditPlan) {
        use(makeLook(plan: plan))
    }

    func use(_ next: Look) {
        lock.lock()
        if next.canvasSize != look.canvasSize { previousLook = look }
        look = next
        lock.unlock()
    }

    /// The look to draw a frame with: the one made for the size of the buffer it goes into.
    private func look(for output: CVPixelBuffer) -> Look {
        let size = CGSize(width: CVPixelBufferGetWidth(output), height: CVPixelBufferGetHeight(output))
        lock.lock()
        defer { lock.unlock() }
        if look.canvasSize != size, let previousLook, previousLook.canvasSize == size { return previousLook }
        return look
    }

    /// Everything a plan needs to draw frames. It can take a while, so the editor does this away from the main thread.
    func makeLook(plan: EditPlan) -> Look {
        let style = plan.settings.style
        // The canvas takes the shape of the project's own recording; attached ones are drawn into it the same way.
        let primary = assets[nil]!
        let layout = Self.fullLayout(displayWidth: primary.displayWidth, displayHeight: primary.displayHeight, style: style,
                                     hasCamera: Self.usesCameraPanel(style, hasWebcam: hasWebcam))
        let canvas = layout.canvas
        let canvasRect = CGRect(origin: .zero, size: canvas)
        let device = layout.device
        let mockup = mockupLook(style: style, canvas: canvas, padding: (style.padding * canvas.width / 2).rounded() * 2)

        let mask = Self.roundedRectImage(canvas: canvas, rect: device.maskRect, radius: device.maskRadius, color: CGColor(gray: 1, alpha: 1))

        let cameraMask = layout.camera.map { Self.roundedRectImage(canvas: canvas, rect: $0, radius: style.cornerRadius * canvas.width, color: CGColor(gray: 1, alpha: 1)) } ?? .empty()

        var backdrop = backgroundImage(style.activeBackground, canvas: canvas)
        // A 3D device casts its own shadow, drawn with it for each frame.
        if style.shadowOpacity > 0, mockup == nil {
            let angle = style.shadowAngle * .pi / 180
            let distance = style.shadowDistance * canvas.width
            // The screen's shadow, and the camera panel's if it has one.
            var shapes = [(device.shadowRect, device.shadowRadius)]
            if let camera = layout.camera { shapes.append((camera, style.cornerRadius * canvas.width)) }
            for (rect, shapeRadius) in shapes {
                let shadowRect = rect.offsetBy(dx: cos(angle) * distance, dy: -sin(angle) * distance)
                let shadowShape = Self.roundedRectImage(canvas: canvas, rect: shadowRect, radius: shapeRadius,
                                                        color: CGColor(gray: 0, alpha: style.shadowOpacity))
                let blurred = shadowShape.clampedToExtent()
                    .applyingGaussianBlur(sigma: max(0.01, style.shadowBlur * canvas.width))
                    .cropped(to: canvasRect)
                backdrop = blurred.composited(over: backdrop)
            }
        }
        if mockup == nil, let art = DeviceFrames.art(style.deviceFrame, geometry: device, canvas: canvas) {
            backdrop = art.composited(over: backdrop)
        }
        // Flatten once so each frame only has to draw the picture over a ready-made backdrop.
        if let rendered = context.createCGImage(backdrop, from: canvasRect, format: .RGBA8, colorSpace: colorSpace) {
            backdrop = CIImage(cgImage: rendered)
        }

        let styleCursor = CursorArt.art(for: style.cursorStyle).map { Sprite(image: $0.image, meta: $0.meta, pixelHeight: $0.pixelHeight) }
        return Look(plan: plan, canvasSize: canvas, contentRect: layout.content, backdrop: backdrop, mask: mask,
                    cameraRect: layout.camera, cameraMask: cameraMask, styleCursor: styleCursor, mockup: mockup)
    }

    private var primaryPixelWidth: Int { assets[nil].map { Int($0.displayWidth * $0.pixelScale) } ?? 0 }
    private var primaryPixelHeight: Int { assets[nil].map { Int($0.displayHeight * $0.pixelScale) } ?? 0 }

    private func mockupLook(style: RenderStyle, canvas: CGSize, padding: Double) -> MockupLook? {
        guard let choice = style.mockup, let device = Self.mockupDevice(style), let motion = device.motion(id: choice.motionID) ?? device.defaultMotion,
              let metal, let metalQueue else { return nil }
        lock.lock()
        var renderer = mockupRenderers[device.id]
        lock.unlock()
        if renderer == nil, let url = MockupLibrary.shared.modelURL(id: device.id) {
            renderer = MockupRenderer(modelURL: url, exposure: device.exposure, glow: device.glow, device: metal, queue: metalQueue)
            lock.lock()
            mockupRenderers[device.id] = renderer
            lock.unlock()
        }
        guard let renderer else { return nil }
        let stage = MockupStage.fit(device, canvas: canvas, padding: padding)
        // At least twice the size it appears on the canvas, so a zoom of 2× is still drawn from real pixels. A sharper
        // recording keeps its own pixels: drawn unscaled when the screen has the same shape as the display it came from.
        let rect = stage.screenRect
        let appears = max(rect.width, rect.height)
        let recorded = Double(max(primaryPixelWidth, primaryPixelHeight))
        let longest = isPreview ? min(4096, appears * 2) : min(4096, max(appears * 2, min(recorded, appears * 3)))
        func even(_ value: Double) -> Double { max(2, (value / 2).rounded() * 2) }
        let size = device.screenAspect >= 1
            ? CGSize(width: even(longest), height: even(longest / device.screenAspect))
            : CGSize(width: even(longest * device.screenAspect), height: even(longest))
        return MockupLook(device: device, motion: motion, stage: stage, pictureSize: size, renderer: renderer)
    }

    private func backgroundImage(_ background: BackgroundStyle, canvas: CGSize) -> CIImage {
        let canvasRect = CGRect(origin: .zero, size: canvas)
        func ciColor(_ rgb: RGB) -> CIColor { CIColor(red: rgb.r, green: rgb.g, blue: rgb.b) }

        switch background.kind {
        case .solid:
            return CIImage(color: ciColor(background.solid)).cropped(to: canvasRect)

        case .wallpaper:
            return Wallpapers.image(Wallpapers.wallpaper(id: background.wallpaperID), canvas: canvas)

        case .image:
            // A picture, or an SVG drawn at the size of the canvas.
            let url = background.imageFile.map { bundleFolder.appendingPathComponent($0) }
            guard let url,
                  let cgImage = SVGRaster.cgImage(svgFile: url, size: canvas)
                    ?? CGImageSourceCreateWithURL(url as CFURL, nil).flatMap({ CGImageSourceCreateImageAtIndex($0, 0, nil) }) else {
                return CIImage(color: ciColor(background.solid)).cropped(to: canvasRect)
            }
            // Fill the canvas, cropping the overflow evenly on both sides.
            let image = CIImage(cgImage: cgImage)
            let fill = max(canvas.width / image.extent.width, canvas.height / image.extent.height)
            var scaled = image.transformed(by: CGAffineTransform(scaleX: fill, y: fill))
            scaled = scaled.transformed(by: CGAffineTransform(translationX: (canvas.width - scaled.extent.width) / 2 - scaled.extent.minX,
                                                              y: (canvas.height - scaled.extent.height) / 2 - scaled.extent.minY))
            if background.imageBlur > 0 {
                scaled = scaled.clampedToExtent().applyingGaussianBlur(sigma: background.imageBlur * canvas.width)
            }
            return scaled.cropped(to: canvasRect)

        case .gradient:
            // The gradient line runs through the middle of the canvas, long enough to reach both corners.
            let angle = background.angle * .pi / 180
            let direction = CGPoint(x: cos(angle), y: -sin(angle))
            let halfLength = (abs(canvas.width * cos(angle)) + abs(canvas.height * sin(angle))) / 2
            let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            let gradient = CIFilter.linearGradient()
            gradient.point0 = CGPoint(x: center.x - direction.x * halfLength, y: center.y - direction.y * halfLength)
            gradient.point1 = CGPoint(x: center.x + direction.x * halfLength, y: center.y + direction.y * halfLength)
            gradient.color0 = ciColor(background.gradientTop)
            gradient.color1 = ciColor(background.gradientBottom)
            return gradient.outputImage!.cropped(to: canvasRect)
        }
    }

    private static func roundedRectImage(canvas: CGSize, rect: CGRect, radius: Double, color: CGColor) -> CIImage {
        let width = Int(canvas.width)
        let height = Int(canvas.height)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return CIImage.empty()
        }
        ctx.setFillColor(color)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: min(radius, rect.width / 2), cornerHeight: min(radius, rect.height / 2), transform: nil))
        ctx.fillPath()
        return CIImage(cgImage: ctx.makeImage()!)
    }

    // MARK: Rendering

    func render(source: CVPixelBuffer, webcam: CVPixelBuffer? = nil, outputTime: Double, into output: CVPixelBuffer) {
        let look = look(for: output)
        let plan = look.plan
        let canvasRect = CGRect(origin: .zero, size: look.canvasSize)
        // Which clip, and so which recording and moment, this frame of the video shows.
        guard let location = plan.timeMap.locate(output: outputTime),
              let sourcePlan = plan.sourcePlan(location.segment.sourceID),
              let sourceAssets = assets[location.segment.sourceID] else {
            context.render(look.backdrop, to: output, bounds: canvasRect, colorSpace: colorSpace)
            return
        }
        // Inside a device, the screen is first drawn flat and whole, and it is the 3D camera that moves. So here the
        // screen area is that flat picture, and the camera on it stays at rest.
        let mockup = look.mockup
        let contentRect = mockup.map { CGRect(origin: .zero, size: $0.pictureSize) } ?? look.contentRect
        let t = location.sourceTime
        let style = plan.settings.style
        let crop = style.crop
        let viewCamera = sourcePlan.camera(at: t, crop: crop)
        let camera = mockup == nil ? viewCamera : CameraState(scale: 1, centerX: crop.x + crop.width / 2, centerY: crop.y + crop.height / 2)

        let sourceWidth = Double(CVPixelBufferGetWidth(source))
        let sourceHeight = Double(CVPixelBufferGetHeight(source))
        // The visible part of the screen, in source pixels, is the cropped width divided by the zoom.
        // (A device's screen may be a different shape from the recording, which then fills it, cropped evenly.)
        let k = mockup == nil ? contentRect.width / (sourceWidth * crop.width / camera.scale)
                              : max(contentRect.width / (sourceWidth * crop.width), contentRect.height / (sourceHeight * crop.height))
        let focusX = camera.centerX * sourceWidth
        let focusY = (1 - camera.centerY) * sourceHeight
        let tx = contentRect.midX - focusX * k
        let ty = contentRect.midY - focusY * k

        // Zooming magnifies the whole picture, background and frame included, so a zoomed-in screen fills the video
        // instead of shrinking back inside its padding. The point the camera aims at, where it sits when nothing is
        // zoomed, moves to the middle of the screen area and everything around it scales with it. (With the camera in
        // a panel of its own, only the screen zooms, inside its panel.)
        let zoomsWholePicture = look.cameraRect == nil && mockup == nil
        let anchor = CGPoint(x: contentRect.minX + (camera.centerX - crop.x) / crop.width * contentRect.width,
                             y: contentRect.maxY - (camera.centerY - crop.y) / crop.height * contentRect.height)
        let zoom = zoomsWholePicture
            ? CGAffineTransform(translationX: -anchor.x, y: -anchor.y)
                .concatenating(CGAffineTransform(scaleX: camera.scale, y: camera.scale))
                .concatenating(CGAffineTransform(translationX: contentRect.midX, y: contentRect.midY))
            : .identity
        // Where the (cropped) screen is in the video now.
        let screenRect = zoomsWholePicture ? contentRect.applying(zoom).intersection(canvasRect) : contentRect

        // Hidden regions are applied to the screen picture itself, before it is moved and scaled, so they stay put on it.
        let sourceImage = MaskPainter.apply(to: CIImage(cvPixelBuffer: source), masks: sourcePlan.masks, time: t, size: (sourceWidth, sourceHeight))
        let scaled = sourceImage
            .applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: k, kCIInputAspectRatioKey: 1.0])
        var layer = scaled.transformed(by: CGAffineTransform(translationX: tx, y: ty)).cropped(to: screenRect)
        if mockup == nil {
            layer = motionBlurred(layer, sourcePlan: sourcePlan, plan: plan, location: location, contentRect: contentRect,
                                  region: screenRect, sourceSize: (sourceWidth, sourceHeight), camera: camera)
        }

        let pointsToCanvas = k * sourceWidth / sourceAssets.displayWidth
        let cursorHidden = location.segment.hideCursor

        // A magnifier follows the cursor and shows that part of the screen larger.
        if let lens = sourcePlan.loupe(at: t) {
            let position = sourcePlan.cursor(at: t)
            let center = CGPoint(x: position.x * sourceWidth * k + tx, y: (1 - position.y) * sourceHeight * k + ty)
            layer = magnifier(of: sourceImage, around: position, at: center, scaledBy: k * lens.scale, sourceSize: (sourceWidth, sourceHeight),
                              radius: style.loupeSize * contentRect.width * lens.progress, contentRect: contentRect).composited(over: layer)
        }

        if style.clickEffect, !cursorHidden {
            for click in sourcePlan.clicks where t >= click.t && t < click.t + Self.rippleDuration {
                layer = ripple(for: click, at: t, plan: plan, sourcePlan: sourcePlan, sourceSize: (sourceWidth, sourceHeight), k: k, tx: tx, ty: ty,
                               pointsToCanvas: pointsToCanvas).composited(over: layer)
            }
        }

        if style.showCursor, !cursorHidden, let cursor = look.styleCursor ?? cursorSprite(at: t, assets: sourceAssets, dark: style.cursorStyle == .dark) {
            let position = sourcePlan.cursor(at: t)
            if (0...1).contains(position.x), (0...1).contains(position.y) {
                let canvasX = position.x * sourceWidth * k + tx
                let canvasY = (1 - position.y) * sourceHeight * k + ty
                let scale = pointsToCanvas * style.cursorScale
                let spriteScale = cursor.meta.height * scale / cursor.pixelHeight
                let originX = canvasX - cursor.meta.hotspotX * scale
                let originY = canvasY - (cursor.meta.height - cursor.meta.hotspotY) * scale
                var transform = CGAffineTransform(scaleX: spriteScale, y: spriteScale)
                    .concatenating(CGAffineTransform(translationX: originX, y: originY))
                // Going in on a click and leaning both happen around the tip, which stays exactly where the pointer is.
                let pressed = 1 - Self.cursorPressAmount * sourcePlan.cursorPress(at: t)
                let tilt = style.cursorTilt ? sourcePlan.cursorTilt(at: t) : 0
                if pressed < 0.999 || abs(tilt) > 0.001 {
                    transform = transform.concatenating(CGAffineTransform(translationX: -canvasX, y: -canvasY))
                        .concatenating(CGAffineTransform(scaleX: pressed, y: pressed))
                        .concatenating(CGAffineTransform(rotationAngle: tilt))
                        .concatenating(CGAffineTransform(translationX: canvasX, y: canvasY))
                }
                let placed = cursor.image.transformed(by: transform)
                layer = placed.composited(over: layer)
            }
        }

        // The camera: a bubble or a cut-out person over the screen, drawn on top of the cursor. In a split layout it has a panel of its own, drawn below.
        if style.showWebcam, let webcam, !style.cameraLayout.isSplit || mockup != nil {
            if style.cameraLayout == .cutout, let person = cutoutPerson(webcam, plan: plan, contentRect: contentRect) {
                layer = person.composited(over: layer)
            } else {
                // A bubble, or the fallback when the person could not be told apart from the background.
                layer = webcamBubble(webcam, cameraScale: viewCamera.scale, plan: plan, contentRect: contentRect).composited(over: layer)
            }
        }

        // Captions go over everything on the screen, inside its edges.
        if style.showCaptions, let line = sourcePlan.caption(at: t),
           let caption = captionImage(line, style: style, canvasWidth: mockup == nil ? canvasRect.width : contentRect.width, contentRect: contentRect, time: t) {
            layer = caption.composited(over: layer)
        }

        if let mockup {
            // Where the camera is aiming, as a spot on the device's screen.
            let aim = (u: (viewCamera.centerX * sourceWidth * k + tx) / contentRect.width,
                       v: ((1 - viewCamera.centerY) * sourceHeight * k + ty) / contentRect.height)
            drawMockup(mockup, picture: layer.cropped(to: contentRect), look: look, scale: viewCamera.scale, aim: aim, outputTime: outputTime, into: output)
            return
        }

        // Clip the picture to the rounded shape first, then lay it over the backdrop. Blending straight
        // onto the backdrop would turn the parts of the shape the picture does not cover (a browser's
        // title bar) black.
        let nothing = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: canvasRect)
        let mask = zoomsWholePicture ? look.mask.transformed(by: zoom).cropped(to: canvasRect) : look.mask
        let backdrop = zoomsWholePicture ? look.backdrop.clampedToExtent().transformed(by: zoom).cropped(to: canvasRect) : look.backdrop
        let clipped = layer.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: nothing,
            kCIInputMaskImageKey: mask,
        ])
        var composed = clipped.composited(over: backdrop)
        if let cameraRect = look.cameraRect {
            composed = cameraPanel(webcam, in: cameraRect, mask: look.cameraMask, mirror: style.webcamMirror, canvas: canvasRect).composited(over: composed)
        }
        context.render(composed, to: output, bounds: canvasRect, colorSpace: colorSpace)
    }

    // MARK: Device mockups

    /// The video inside a 3D device. Zooming magnifies the whole picture, as it does without a device: the spot the
    /// camera aims at moves to where the middle of the screen sits at rest, and everything around it scales with it.
    private func drawMockup(_ mockup: MockupLook, picture: CIImage, look: Look, scale requested: Double, aim: (u: Double, v: Double),
                            outputTime: Double, into output: CVPixelBuffer) {
        let canvasRect = CGRect(origin: .zero, size: look.canvasSize)
        let style = look.plan.settings.style
        // Zooms wait for the device to arrive, so that they never cut its entrance short.
        let settled = min(1, max(0, (outputTime - mockup.motion.settle + 0.2) / 1.0))
        let scale = 1 + (requested - 1) * settled * settled * (3 - 2 * settled)
        let anchor = mockup.stage.screenPoint(u: aim.u, v: aim.v)
        let middle = mockup.stage.screenPoint(u: 0.5, v: 0.5)
        let zoom = CGAffineTransform(translationX: -anchor.x, y: -anchor.y)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: middle.x, y: middle.y))
        let backdrop = look.backdrop.clampedToExtent().transformed(by: zoom).cropped(to: canvasRect)
        let poses = Self.shutterPoses(mockup, at: outputTime, fps: style.fps, most: isPreview ? 6 : 16)

        mockup.renderer.render(picture: picture, pictureSize: mockup.pictureSize, context: context, stage: mockup.stage, poses: poses,
                               supersampling: MockupRenderer.supersampling(for: mockup.stage.canvas, most: isPreview ? 1.5 : 2), zoom: zoom) { device in
            var composed = backdrop
            if style.shadowOpacity > 0 {
                // The Shadow settings apply to the shape of the device, whatever pose it is in.
                let angle = style.shadowAngle * .pi / 180
                let distance = style.shadowDistance * canvasRect.width * scale
                let shadow = device
                    .applyingFilter("CIColorMatrix", parameters: [
                        "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                        "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: style.shadowOpacity)])
                    .applyingGaussianBlur(sigma: max(0.01, style.shadowBlur * canvasRect.width * scale))
                    .transformed(by: CGAffineTransform(translationX: cos(angle) * distance, y: -sin(angle) * distance))
                    .cropped(to: canvasRect)
                composed = shadow.composited(over: composed)
            }
            context.render(device.composited(over: composed), to: output, bounds: canvasRect, colorSpace: colorSpace)
        }
    }

    /// The moments a camera's shutter would see during this frame. Fast moves are drawn several times and averaged, which
    /// is what makes them look filmed; a slow drift needs just one. The shutter is open for under a third of the frame,
    /// because a film's usual half smears the video on the screen too much to read as sharp.
    private static func shutterPoses(_ mockup: MockupLook, at time: Double, fps: Int, most: Int) -> [MockupPose] {
        let shutter = 0.3 / Double(max(fps, 1))
        // Pixels on the canvas the fastest part of the device covers while the shutter is open. Under a pixel and a half
        // there is nothing to see, and blurring would only soften the video's text.
        let start = mockup.motion.pose(at: time), end = mockup.motion.pose(at: time + shutter)
        let turn = Double(abs(simd_mul(end.rotation, start.rotation.inverse).angle.truncatingRemainder(dividingBy: 2 * .pi)))
        let shortest = min(turn, 2 * .pi - turn)
        let metres = Double(simd_length(end.position - start.position)) + mockup.stage.reach * (shortest + Double(abs(end.lid - start.lid)))
        let pixels = metres * mockup.stage.pixelsPerMetre
        guard pixels >= 1.5 else { return [start] }
        // Close enough together that they read as a smooth streak, not as separate copies.
        let count = min(most, max(2, Int((pixels / 1.5).rounded(.up))))
        return (0..<count).map { mockup.motion.pose(at: time + shutter * Double($0) / Double(count)) }
    }

    // MARK: Captions

    /// The words of a caption on a rounded dark plate, placed near the bottom or top of the screen and faded at its ends.
    private func captionImage(_ line: CaptionLine, style: RenderStyle, canvasWidth: Double, contentRect: CGRect, time: Double) -> CIImage? {
        let fontSize = max(8, style.captionSize * canvasWidth)
        let maxWidth = contentRect.width * 0.84
        let key = "\(line.text)|\(Int(fontSize))|\(Int(maxWidth))|\(style.captionBold)|\(style.captionBackground)|\(style.captionColor.r),\(style.captionColor.g),\(style.captionColor.b)"

        captionLock.lock()
        var entry = captionCache[key]
        captionLock.unlock()
        if entry == nil {
            guard let made = Self.drawCaption(line.text, fontSize: fontSize, maxWidth: maxWidth, style: style) else { return nil }
            captionLock.lock()
            if captionCache.count > 24 { captionCache.removeAll() }
            captionCache[key] = made
            captionLock.unlock()
            entry = made
        }
        guard let entry else { return nil }

        let margin = contentRect.height * 0.045
        let y = style.captionPosition == .bottom ? contentRect.minY + margin : contentRect.maxY - margin - entry.size.height
        let fade = 0.12
        let opacity = min(1, max(0, min((time - line.start) / fade, (line.end - time) / fade)))
        guard opacity > 0 else { return nil }
        return entry.image
            .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity)])
            .transformed(by: CGAffineTransform(translationX: (contentRect.midX - entry.size.width / 2).rounded(), y: y.rounded()))
    }

    /// Draws the caption text, wrapped to `maxWidth`, onto its plate.
    private static func drawCaption(_ text: String, fontSize: Double, maxWidth: Double, style: RenderStyle) -> (image: CIImage, size: CGSize)? {
        let font = NSFont.systemFont(ofSize: fontSize, weight: style.captionBold ? .semibold : .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        let color = NSColor(srgbRed: style.captionColor.r, green: style.captionColor.g, blue: style.captionColor.b, alpha: 1)
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])

        let paddingX = style.captionBackground ? fontSize * 0.7 : 0
        let paddingY = style.captionBackground ? fontSize * 0.4 : 0
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let fit = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(), nil, CGSize(width: maxWidth - 2 * paddingX, height: .greatestFiniteMagnitude), nil)
        let textWidth = ceil(fit.width), textHeight = ceil(fit.height)
        let width = Int(ceil(textWidth + 2 * paddingX)) + 2, height = Int(ceil(textHeight + 2 * paddingY)) + 2

        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        if style.captionBackground {
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.66))
            ctx.addPath(CGPath(roundedRect: CGRect(x: 1, y: 1, width: width - 2, height: height - 2),
                               cornerWidth: fontSize * 0.5, cornerHeight: fontSize * 0.5, transform: nil))
            ctx.fillPath()
        } else {
            // Without a plate, a soft shadow keeps the words readable on any picture.
            ctx.setShadow(offset: CGSize(width: 0, height: -fontSize * 0.06), blur: fontSize * 0.25, color: CGColor(gray: 0, alpha: 0.85))
        }
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(),
                                             CGPath(rect: CGRect(x: paddingX + 1, y: paddingY + 1, width: textWidth, height: textHeight), transform: nil), nil)
        CTFrameDraw(frame, ctx)
        guard let drawn = ctx.makeImage() else { return nil }
        return (CIImage(cgImage: drawn), CGSize(width: width, height: height))
    }

    // MARK: Magnifier

    /// A round lens that shows the screen around `position` (normalized) `magnification` times larger,
    /// centered on `center` (canvas pixels), with a rim and a soft shadow.
    private func magnifier(of image: CIImage, around position: SIMD2<Double>, at center: CGPoint, scaledBy magnification: Double,
                           sourceSize: (Double, Double), radius: Double, contentRect: CGRect) -> CIImage {
        guard radius > 2 else { return .empty() }
        let lensRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let bounds = lensRect.insetBy(dx: -radius * 0.5, dy: -radius * 0.5)

        // The screen enlarged so the cursor's spot stays under the middle of the lens.
        let enlarged = image
            .applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: magnification, kCIInputAspectRatioKey: 1.0])
            .transformed(by: CGAffineTransform(translationX: center.x - position.x * sourceSize.0 * magnification,
                                               y: center.y - (1 - position.y) * sourceSize.1 * magnification))
            .cropped(to: lensRect)

        func disc(_ rect: CGRect, color: CIColor) -> CIImage {
            let generator = CIFilter.roundedRectangleGenerator()
            generator.extent = rect
            generator.radius = Float(rect.width / 2)
            generator.color = color
            return generator.outputImage!
        }
        let clear = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: bounds)

        // A faint highlight toward the top-left, like light on glass.
        let highlight = CIFilter.radialGradient()
        highlight.center = CGPoint(x: center.x - radius * 0.35, y: center.y + radius * 0.35)
        highlight.radius0 = 0
        highlight.radius1 = Float(radius * 0.9)
        highlight.color0 = CIColor(red: 1, green: 1, blue: 1, alpha: 0.16)
        highlight.color1 = CIColor(red: 1, green: 1, blue: 1, alpha: 0)
        let lens = highlight.outputImage!.cropped(to: lensRect).composited(over: enlarged)
            .applyingFilter("CIBlendWithAlphaMask", parameters: [
                kCIInputBackgroundImageKey: clear,
                kCIInputMaskImageKey: disc(lensRect, color: CIColor(red: 1, green: 1, blue: 1, alpha: 1)),
            ])

        let rim = max(2, radius * 0.045)
        let ring = disc(lensRect.insetBy(dx: -rim, dy: -rim), color: CIColor(red: 1, green: 1, blue: 1, alpha: 0.95))
        let shadow = disc(lensRect.offsetBy(dx: 0, dy: -radius * 0.07), color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.4))
            .composited(over: clear).applyingGaussianBlur(sigma: radius * 0.12).cropped(to: bounds)
        return lens.composited(over: ring).composited(over: shadow)
    }

    // MARK: Camera layouts

    /// The webcam filling a panel, cropped to fit, with the panel's rounded shape. Without a picture (the webcam has
    /// not started yet, or has ended) the panel is dark rather than disappearing, so the layout does not jump.
    private func cameraPanel(_ webcam: CVPixelBuffer?, in rect: CGRect, mask: CIImage, mirror: Bool, canvas: CGRect) -> CIImage {
        var picture: CIImage
        if let webcam {
            var image = CIImage(cvPixelBuffer: webcam)
            if mirror { image = image.oriented(.upMirrored) }
            let fill = max(rect.width / image.extent.width, rect.height / image.extent.height)
            image = image.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: fill, kCIInputAspectRatioKey: 1.0])
            picture = image.transformed(by: CGAffineTransform(translationX: rect.midX - image.extent.midX, y: rect.midY - image.extent.midY)).cropped(to: rect)
        } else {
            picture = CIImage(color: CIColor(red: 0.09, green: 0.09, blue: 0.1)).cropped(to: rect)
        }
        let nothing = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: canvas)
        return picture.applyingFilter("CIBlendWithAlphaMask", parameters: [kCIInputBackgroundImageKey: nothing, kCIInputMaskImageKey: mask])
    }

    /// The share (0...1) of a one-channel matte that is mostly person, sampled sparsely.
    private static func coverage(of matte: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(matte, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(matte, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(matte) else { return 0 }
        let width = CVPixelBufferGetWidth(matte), height = CVPixelBufferGetHeight(matte)
        let stride = CVPixelBufferGetBytesPerRow(matte)
        var inside = 0, total = 0
        for y in Swift.stride(from: 0, to: height, by: 4) {
            let row = base.advanced(by: y * stride).assumingMemoryBound(to: UInt8.self)
            for x in Swift.stride(from: 0, to: width, by: 4) {
                total += 1
                if row[x] > 127 { inside += 1 }
            }
        }
        return total > 0 ? Double(inside) / Double(total) : 0
    }

    /// The person from the webcam, without their background, standing in a bottom corner of the screen.
    /// Nil if the person could not be told apart from the background.
    private func cutoutPerson(_ webcam: CVPixelBuffer, plan: EditPlan, contentRect: CGRect) -> CIImage? {
        let style = plan.settings.style
        let request = VNGeneratePersonSegmentationRequest()
        // Fast while previewing, accurate when the picture is large (exporting).
        request.qualityLevel = style.maxOutputWidth <= 1400 ? .fast : .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        guard (try? VNImageRequestHandler(cvPixelBuffer: webcam, options: [:]).perform([request])) != nil,
              let result = request.results?.first,
              Self.coverage(of: result.pixelBuffer) >= 0.02 else { return nil }

        var picture = CIImage(cvPixelBuffer: webcam)
        let frame = picture.extent
        var matte = CIImage(cvPixelBuffer: result.pixelBuffer)
        matte = matte.transformed(by: CGAffineTransform(scaleX: frame.width / matte.extent.width, y: frame.height / matte.extent.height))
            // A touch of blur so the edge of the person is soft, not jagged.
            .clampedToExtent().applyingGaussianBlur(sigma: 1.6).cropped(to: frame)
            .applyingFilter("CIMaskToAlpha")
        let nothing = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: frame)
        picture = picture.applyingFilter("CIBlendWithAlphaMask", parameters: [kCIInputBackgroundImageKey: nothing, kCIInputMaskImageKey: matte])
        if style.webcamMirror { picture = picture.oriented(.upMirrored) }

        // Scaled so the picture is a given share of the screen's height, standing on the bottom edge of the screen.
        let scale = style.cutoutSize * contentRect.height / frame.height
        let width = frame.width * scale
        let onRight = style.webcamCorner == .bottomRight || style.webcamCorner == .topRight
        let x = onRight ? contentRect.maxX - width : contentRect.minX
        return picture
            .applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1.0])
            .transformed(by: CGAffineTransform(translationX: x, y: contentRect.minY))
    }

    /// Smears the picture along the direction the camera is moving, and outward while it zooms, the way a
    /// real camera would during one frame's exposure.
    /// How Core Image's blur filters relate their settings to the length of the streak they draw.
    static let zoomBlurScale = 46.0
    static let motionBlurSpread = 6.0

    private func motionBlurred(_ layer: CIImage, sourcePlan: SourcePlan, plan: EditPlan, location: TimeMap.Location,
                               contentRect: CGRect, region: CGRect, sourceSize: (Double, Double), camera: CameraState) -> CIImage {
        let amount = plan.settings.style.motionBlur
        guard amount > 0.001 else { return layer }

        // The picture's movement during one frame of the video, as a camera shutter open for part of that frame
        // would catch it: half the frame at the default setting. Enough to sell the motion, light enough that the
        // picture stays readable through the steady middle of a move.
        let shutter = amount
        let interval = location.segment.speed / Double(max(1, plan.settings.style.fps))
        let t = location.sourceTime
        let crop = plan.settings.style.crop
        let before = sourcePlan.camera(at: t - interval / 2, crop: crop)
        let after = sourcePlan.camera(at: t + interval / 2, crop: crop)

        // Scale (canvas pixels per source pixel) and where a source point lands on the canvas, for a camera state.
        func scale(_ state: CameraState) -> Double { contentRect.width / (sourceSize.0 * crop.width / state.scale) }
        func source(_ state: CameraState) -> CGPoint { CGPoint(x: state.centerX * sourceSize.0, y: (1 - state.centerY) * sourceSize.1) }
        func canvas(_ point: CGPoint, _ state: CameraState) -> CGPoint {
            let k = scale(state), c = source(state)
            return CGPoint(x: contentRect.midX + (point.x - c.x) * k, y: contentRect.midY + (point.y - c.y) * k)
        }
        let kBefore = scale(before), kAfter = scale(after)
        let zoomRatio = abs(kAfter - kBefore) / max(kBefore, kAfter)
        // Blur never gets so strong that the picture turns to mush.
        let limit = contentRect.width * 0.015

        if zoomRatio > 0.0005 {
            // Zooming: everything streaks toward the one point that stays still between the two moments.
            let a = source(before), b = source(after)
            let still = CGPoint(x: (a.x * kBefore - b.x * kAfter) / (kBefore - kAfter), y: (a.y * kBefore - b.y * kAfter) / (kBefore - kAfter))
            var center = canvas(still, after)
            center.x = min(max(center.x, contentRect.minX), contentRect.maxX)
            center.y = min(max(center.y, contentRect.minY), contentRect.maxY)
            // How far a point at the far edge travels during the shutter.
            let reach = max(hypot(contentRect.minX - center.x, contentRect.minY - center.y), hypot(contentRect.maxX - center.x, contentRect.maxY - center.y))
            let streak = min(limit, zoomRatio * reach * shutter)
            guard streak > 0.5, reach > 1 else { return layer }
            // Core Image's zoom blur streaks a point `amount × distance / 46` pixels long (measured), so this
            // makes the streak at the far edge exactly `streak` pixels.
            return layer.clampedToExtent()
                .applyingFilter("CIZoomBlur", parameters: [kCIInputCenterKey: CIVector(x: center.x, y: center.y),
                                                           kCIInputAmountKey: streak * Self.zoomBlurScale / reach])
                .cropped(to: region)
        }

        // Panning: streak along the direction the picture moves.
        let middle = source(camera)
        let start = canvas(middle, before), end = canvas(middle, after)
        let streak = min(limit, hypot(end.x - start.x, end.y - start.y) * shutter)
        guard streak > 0.5 else { return layer }
        // Core Image's motion blur smears about six times its radius (measured), so the radius is a sixth of the streak.
        return layer.clampedToExtent()
            .applyingFilter("CIMotionBlur", parameters: [kCIInputRadiusKey: streak / Self.motionBlurSpread,
                                                         kCIInputAngleKey: atan2(end.y - start.y, end.x - start.x)])
            .cropped(to: region)
    }


    private func cursorSprite(at time: Double, assets: SourceAssets, dark: Bool) -> Sprite? {
        let pictures = dark ? assets.darkSprites : assets.sprites
        // Last shape change at or before `time`.
        var low = 0
        var high = assets.cursorChanges.count
        while low < high {
            let mid = (low + high) / 2
            if assets.cursorChanges[mid].t <= time { low = mid + 1 } else { high = mid }
        }
        if low > 0, let sprite = pictures[assets.cursorChanges[low - 1].id] { return sprite }
        return pictures[assets.cursorChanges.first?.id ?? ""] ?? pictures.values.first
    }

    // MARK: Webcam

    /// The camera view with a thin white ring and a soft shadow, anchored to a corner of the screen
    /// area. It shrinks while the camera is zoomed in.
    private func webcamBubble(_ frame: CVPixelBuffer, cameraScale: Double, plan: EditPlan, contentRect: CGRect) -> CIImage {
        let style = plan.settings.style
        let zoomRange = max(0.01, plan.settings.zoomScale - 1)
        let zoomProgress = min(1, max(0, (cameraScale - 1) / zoomRange))
        let sizeFactor = 1 + (style.webcamZoomedScale - 1) * zoomProgress

        let diameter = style.webcamSize * contentRect.width * sizeFactor
        let margin = style.webcamMargin * contentRect.width
        let radius = diameter / 2
        let center: CGPoint
        switch style.webcamCorner {
        case .bottomRight: center = CGPoint(x: contentRect.maxX - margin - radius, y: contentRect.minY + margin + radius)
        case .bottomLeft: center = CGPoint(x: contentRect.minX + margin + radius, y: contentRect.minY + margin + radius)
        case .topRight: center = CGPoint(x: contentRect.maxX - margin - radius, y: contentRect.maxY - margin - radius)
        case .topLeft: center = CGPoint(x: contentRect.minX + margin + radius, y: contentRect.maxY - margin - radius)
        }
        let cornerRadius = style.webcamShape == .circle ? radius : diameter * 0.22

        // Center-crop the camera to a square, then scale it to the bubble.
        var image = CIImage(cvPixelBuffer: frame)
        let side = min(image.extent.width, image.extent.height)
        image = image.cropped(to: CGRect(x: image.extent.midX - side / 2, y: image.extent.midY - side / 2, width: side, height: side))
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        if style.webcamMirror { image = image.oriented(.upMirrored) }
        image = image
            .applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: diameter / side, kCIInputAspectRatioKey: 1.0])
            .transformed(by: CGAffineTransform(translationX: center.x - radius, y: center.y - radius))

        func shape(_ rect: CGRect, radius: Double, color: CIColor) -> CIImage {
            let generator = CIFilter.roundedRectangleGenerator()
            generator.extent = rect
            generator.radius = Float(radius)
            generator.color = color
            return generator.outputImage!
        }
        let bubbleRect = CGRect(x: center.x - radius, y: center.y - radius, width: diameter, height: diameter)
        let bounds = bubbleRect.insetBy(dx: -radius * 0.6, dy: -radius * 0.6)

        let white = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        let clear = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: bounds)
        let bubble = image.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: clear,
            kCIInputMaskImageKey: shape(bubbleRect, radius: cornerRadius, color: white),
        ])

        let ringWidth = max(2, 0.004 * contentRect.width)
        let ring = shape(bubbleRect.insetBy(dx: -ringWidth, dy: -ringWidth), radius: cornerRadius + ringWidth,
                         color: CIColor(red: 1, green: 1, blue: 1, alpha: 0.95))
        // The shape is laid on transparent padding before blurring. Stretching its edges outward instead
        // would smear the shadow into streaks.
        let shadow = shape(bubbleRect.offsetBy(dx: 0, dy: -radius * 0.08), radius: cornerRadius,
                           color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.4))
            .composited(over: clear)
            .applyingGaussianBlur(sigma: radius * 0.18)
            .cropped(to: bounds)

        return bubble
            .composited(over: ring)
            .composited(over: shadow)
    }

    // MARK: Click ripple

    static let rippleDuration = 0.5
    /// How much smaller the cursor gets at the bottom of a click.
    static let cursorPressAmount = 0.18

    private func ripple(for click: ClickEvent, at time: Double, plan: EditPlan, sourcePlan: SourcePlan, sourceSize: (Double, Double), k: Double,
                        tx: Double, ty: Double, pointsToCanvas: Double) -> CIImage {
        let progress = min(1, (time - click.t) / Self.rippleDuration)
        let eased = 1 - pow(1 - progress, 3)
        let radius = (14 + 46 * eased) * pointsToCanvas
        let alpha = 0.6 * (1 - progress)
        // Centered on the drawn cursor, not the raw click point: the smoothed cursor can still
        // be a few pixels short of the click when it lands, and the two must agree on screen.
        let position = sourcePlan.cursor(at: click.t)
        let center = CGPoint(x: position.x * sourceSize.0 * k + tx, y: (1 - position.y) * sourceSize.1 * k + ty)
        let color = plan.settings.style.clickColor

        let gradient = CIFilter.radialGradient()
        gradient.center = center
        gradient.radius0 = Float(radius * 0.55)
        gradient.radius1 = Float(radius)
        gradient.color0 = CIColor(red: color.r, green: color.g, blue: color.b, alpha: alpha)
        gradient.color1 = CIColor(red: color.r, green: color.g, blue: color.b, alpha: 0)
        return gradient.outputImage!.cropped(to: CGRect(x: center.x - radius, y: center.y - radius,
                                                        width: radius * 2, height: radius * 2))
    }
}
