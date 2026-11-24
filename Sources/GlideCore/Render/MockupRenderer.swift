import AppKit
import CoreImage
import Metal
import SceneKit
import simd

/// Draws one device in 3D, with a picture on its screen, into a Metal texture. The model comes from Blender; its pose
/// comes from the motion. Zooming is done in the lens rather than by enlarging a finished picture, so the device and
/// its screen stay sharp however far the camera goes in.
final class MockupRenderer: @unchecked Sendable {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let renderer: SCNRenderer
    private let scene: SCNScene
    private let rig: SCNNode
    private let lid: SCNNode?
    private let screen: SCNNode
    /// The sheet over a laptop's deck that shows the light falling on it from the screen.
    private let glowSheet: SCNNode?
    private let glowStrength: Double
    private var glowTexture: MTLTexture?
    private var glowView: MTLTexture?
    private let camera = SCNCamera()
    private let cameraNode = SCNNode()
    private let lock = NSLock()

    /// The screen's picture: Core Image writes sRGB bytes into this one, and SceneKit reads them through `screenView`,
    /// which is the same memory seen as sRGB, so the colors come out as they went in.
    private var screenTexture: MTLTexture?
    private var screenView: MTLTexture?
    /// One for each moment the shutter samples.
    private var colorTextures: [MTLTexture] = []
    private var sampledTexture: MTLTexture?
    private var depthTexture: MTLTexture?

    private static let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
    private static let encoded = CGColorSpace(name: CGColorSpace.sRGB)!

    init?(modelURL: URL, exposure: Double = 1, glow: Double = 0, device: MTLDevice, queue: MTLCommandQueue) {
        guard let loaded = try? SCNScene(url: modelURL, options: nil) else { return nil }
        self.device = device
        self.queue = queue

        // Everything is kept in Blender's axes under one node, turned so that Blender's "up" is SceneKit's.
        let world = SCNNode()
        world.eulerAngles.x = -.pi / 2
        for child in loaded.rootNode.childNodes {
            child.removeFromParentNode()
            world.addChildNode(child)
        }
        let scene = SCNScene()
        scene.rootNode.addChildNode(world)
        self.scene = scene

        guard let rig = world.childNode(withName: "Rig", recursively: true),
              let screenHolder = world.childNode(withName: "Screen", recursively: true),
              let screen = Self.firstGeometry(in: screenHolder) else { return nil }
        self.rig = rig
        self.screen = screen
        lid = world.childNode(withName: "Lid", recursively: true)
        glowSheet = world.childNode(withName: "ScreenGlow", recursively: true).flatMap { Self.firstGeometry(in: $0) }
        glowStrength = glow

        Self.forEachMaterial(in: world) { material in
            material.lightingModel = .physicallyBased
            for property in [material.diffuse, material.metalness, material.roughness, material.normal] {
                property.minificationFilter = .linear
                property.magnificationFilter = .linear
                property.mipFilter = .linear
                property.maxAnisotropy = 16
            }
            // Seen this low, a plastic key mirrors far more of the room than it does looking down on it; a real one
            // has a texture that scatters that away.
            if material.name?.hasPrefix("Keycap") == true {
                // Backlit legends: the same picture glows, so they read as clean bright marks at any angle.
                material.emission.contents = material.diffuse.contents
                material.emission.intensity = 0.62
                material.emission.minificationFilter = .linear
                material.emission.magnificationFilter = .linear
                material.emission.mipFilter = .linear
                material.emission.maxAnisotropy = 16
                material.diffuse.contents = NSColor(srgbRed: 0.047, green: 0.047, blue: 0.055, alpha: 1)
                material.shaderModifiers = [.fragment: "_output.color.rgb = _surface.emission.rgb + max(_output.color.rgb - _surface.emission.rgb, float3(0.0)) * 0.26;"]
            }
            if material.name?.hasPrefix("TouchID") == true {
                material.multiply.contents = NSColor(white: 0.55, alpha: 1)
            }
            // The display's black surround has the same coating as the display.
            if material.name?.hasPrefix("BezelGlass") == true || material.name?.hasPrefix("IslandBlack") == true {
                material.multiply.contents = NSColor(white: 0.5, alpha: 1)
            }
        }

        // The screen glows with exactly the picture it is given, and is glass on top of that: it stays true to the
        // video, and a turning device still catches the studio's lights.
        let surface = SCNMaterial()
        surface.lightingModel = .physicallyBased
        surface.diffuse.contents = NSColor.black
        surface.metalness.contents = 0.0
        surface.roughness.contents = 0.06
        // A coated display: it catches the lights, but only faintly, and never hides the picture.
        surface.shaderModifiers = [.fragment: "_output.color.rgb = _surface.emission.rgb + max(_output.color.rgb - _surface.emission.rgb, float3(0.0)) * 0.22;"]
        surface.emission.minificationFilter = .linear
        surface.emission.magnificationFilter = .linear
        surface.emission.mipFilter = .linear
        surface.emission.maxAnisotropy = 16
        // Core Image's rows run bottom to top; SceneKit expects them top to bottom.
        surface.emission.contentsTransform = SCNMatrix4Translate(SCNMatrix4MakeScale(1, -1, 1), 0, 1, 0)
        surface.emission.wrapT = .clamp
        surface.emission.wrapS = .clamp
        screen.geometry?.materials = [surface]

        if let glowSheet {
            let light = SCNMaterial()
            light.lightingModel = .constant
            light.blendMode = .add
            light.writesToDepthBuffer = false
            light.diffuse.contentsTransform = SCNMatrix4Translate(SCNMatrix4MakeScale(1, -1, 1), 0, 1, 0)
            light.diffuse.wrapS = .clamp
            light.diffuse.wrapT = .clamp
            light.multiply.contents = Self.glowFalloff()
            light.multiply.wrapS = .clamp
            light.multiply.wrapT = .clamp
            glowSheet.geometry?.materials = [light]
        }

        camera.zNear = 0.1
        camera.zFar = 20
        cameraNode.camera = camera
        // Looks along Blender's +Y with Blender's +Z up, which is SceneKit's default view once the world is turned.
        cameraNode.eulerAngles.x = .pi / 2
        world.addChildNode(cameraNode)

        // The studio is real HDR, built with the models: it is what makes metal look like metal.
        scene.lightingEnvironment.contents = modelURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("studio.hdr")
        scene.lightingEnvironment.intensity = exposure

        renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = cameraNode
        renderer.autoenablesDefaultLighting = false
    }

    private static func forEachMaterial(in node: SCNNode, _ body: (SCNMaterial) -> Void) {
        node.geometry?.materials.forEach(body)
        for child in node.childNodes { forEachMaterial(in: child, body) }
    }

    private static func firstGeometry(in node: SCNNode) -> SCNNode? {
        if node.geometry != nil { return node }
        for child in node.childNodes {
            if let found = firstGeometry(in: child) { return found }
        }
        return nil
    }

    /// How the screen's light fades from the hinge toward the front of the deck, and toward its sides.
    private static func glowFalloff() -> CGImage? {
        let size = 64
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        for row in 0..<size {
            // Rows run from the image's top, which is the hinge end of the sheet.
            let along = Double(row) / Double(size - 1)
            let fade = pow(1 - along, 1.7)
            for column in 0..<size {
                let across = abs(Double(column) / Double(size - 1) - 0.5) * 2
                let sides = 1 - pow(across, 5) * 0.65
                bytes[row * context.bytesPerRow + column] = UInt8(min(255, 255 * fade * sides))
            }
        }
        return context.makeImage()
    }

    /// How much bigger than the canvas the device is drawn before being scaled down. Multisampling only smooths the edges
    /// of shapes; this is what keeps the video's small text, the key legends and the thin highlights along metal edges clean,
    /// and it means the screen's picture is read at its full resolution instead of from a blurrier mip level.
    static func supersampling(for canvas: CGSize, most: CGFloat = 2) -> CGFloat {
        min(most, max(1, (maximumRenderPixels / max(1, canvas.width * canvas.height)).squareRoot()))
    }

    /// About 5120 x 5120: the point past which the extra detail isn't worth the time per frame.
    private static let maximumRenderPixels: CGFloat = 26_500_000

    /// Makes the textures for this size, and returns whether any are new.
    private func ensureTextures(canvas: CGSize, screenSize: CGSize, samples: Int) -> Bool {
        var made = false
        let width = Int(canvas.width), height = Int(canvas.height)
        // On Apple silicon the multisampled pass lives in tile memory alone, so that these sizes cost no real memory.
        let attachmentStorage: MTLStorageMode = device.supportsFamily(.apple3) ? .memoryless : .private
        if colorTextures.first?.width != width || colorTextures.first?.height != height {
            made = true
            colorTextures = []
            let sampled = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: false)
            sampled.textureType = .type2DMultisample
            sampled.sampleCount = 4
            sampled.usage = [.renderTarget]
            sampled.storageMode = attachmentStorage
            sampledTexture = device.makeTexture(descriptor: sampled)

            let depth = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: width, height: height, mipmapped: false)
            depth.textureType = .type2DMultisample
            depth.sampleCount = 4
            depth.usage = [.renderTarget]
            depth.storageMode = attachmentStorage
            depthTexture = device.makeTexture(descriptor: depth)
        }
        while colorTextures.count < samples {
            let color = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: false)
            color.usage = [.renderTarget, .shaderRead]
            color.storageMode = .private
            guard let texture = device.makeTexture(descriptor: color) else { break }
            colorTextures.append(texture)
        }
        let screenWidth = Int(screenSize.width), screenHeight = Int(screenSize.height)
        if screenTexture?.width != screenWidth || screenTexture?.height != screenHeight {
            made = true
            let picture = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: screenWidth, height: screenHeight, mipmapped: true)
            picture.usage = [.renderTarget, .shaderRead, .shaderWrite, .pixelFormatView]
            picture.storageMode = .private
            screenTexture = device.makeTexture(descriptor: picture)
            screenView = screenTexture?.makeTextureView(pixelFormat: .bgra8Unorm_srgb)
        }
        return made
    }

    /// What the deck sees of the screen: the screen's lower part, blurred as brushed metal would blur it. Only a fairly
    /// open lid shines onto the deck.
    private func renderGlow(picture: CIImage, pictureSize: CGSize, context: CIContext, commands: MTLCommandBuffer, pose: MockupPose) {
        guard let glowSheet else { return }
        let width = 96, height = 48
        if glowTexture == nil {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite, .pixelFormatView]
            descriptor.storageMode = .private
            glowTexture = device.makeTexture(descriptor: descriptor)
            glowView = glowTexture?.makeTextureView(pixelFormat: .bgra8Unorm_srgb)
            glowSheet.geometry?.firstMaterial?.diffuse.contents = glowView
        }
        guard let glowTexture else { return }
        let lower = CGRect(x: 0, y: 0, width: pictureSize.width, height: pictureSize.height * 0.4)
        let small = picture.cropped(to: lower)
            .transformed(by: CGAffineTransform(scaleX: CGFloat(width) / lower.width, y: CGFloat(height) / lower.height))
            .clampedToExtent()
            .applyingGaussianBlur(sigma: 7)
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        context.render(small, to: glowTexture, commandBuffer: commands, bounds: CGRect(x: 0, y: 0, width: width, height: height), colorSpace: Self.encoded)
        // The lid's angle is negative as it opens. No light reaches the deck below about 40 degrees.
        let open = min(1, max(0, (Double(abs(pose.lid)) - 0.7) / 0.9))
        glowSheet.opacity = CGFloat(glowStrength * Double(pose.display) * open * open * (3 - 2 * open))
    }

    /// The projection for a stage, with the canvas-space zoom built into it.
    private static func projection(stage: MockupStage, zoom: CGAffineTransform, near: Double, far: Double) -> SCNMatrix4 {
        let aspect = stage.canvas.width / max(1, stage.canvas.height)
        let f = Float(stage.focal)
        let lens = simd_float4x4(columns: (
            SIMD4(f / Float(aspect), 0, 0, 0),
            SIMD4(0, f, 0, 0),
            SIMD4(0, 0, Float(far / (near - far)), -1),
            SIMD4(0, 0, Float(near * far / (near - far)), 0)))
        // A canvas position X becomes s·X + t. In the lens's -1...1 range, that is s·x + (s - 1 + 2t / width).
        let scaleX = Float(zoom.a), scaleY = Float(zoom.d)
        let shiftX = Float(zoom.a - 1 + 2 * zoom.tx / stage.canvas.width)
        let shiftY = Float(zoom.d - 1 + 2 * zoom.ty / stage.canvas.height)
        let move = simd_float4x4(columns: (
            SIMD4(scaleX, 0, 0, 0),
            SIMD4(0, scaleY, 0, 0),
            SIMD4(0, 0, 1, 0),
            SIMD4(shiftX, shiftY, 0, 1)))
        return SCNMatrix4(move * lens)
    }

    /// Draws the device and hands the result to `body` as an image, which is only valid during the call. With several
    /// poses, one per moment the shutter is open, the frames are averaged, which is what real motion blur is.
    func render(picture: CIImage, pictureSize: CGSize, context: CIContext, stage: MockupStage, poses: [MockupPose], supersampling: CGFloat, zoom: CGAffineTransform, body: (CIImage) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard let first = poses.first else { return }
        let renderSize = CGSize(width: (stage.canvas.width * supersampling).rounded(), height: (stage.canvas.height * supersampling).rounded())
        let isFirstAtThisSize = ensureTextures(canvas: renderSize, screenSize: pictureSize, samples: poses.count)
        guard colorTextures.count >= poses.count, let sampledTexture, let depthTexture, let screenTexture, let screenView,
              let commands = queue.makeCommandBuffer() else { return }

        // The screen's picture. Core Image fills the texture with its origin at the bottom left.
        context.render(picture, to: screenTexture, commandBuffer: commands, bounds: CGRect(origin: .zero, size: pictureSize), colorSpace: Self.encoded)
        renderGlow(picture: picture, pictureSize: pictureSize, context: context, commands: commands, pose: first)
        if let blit = commands.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: screenTexture)
            blit.endEncoding()
        }

        let viewport = CGRect(origin: .zero, size: renderSize)
        // Each sample goes to the GPU on its own: SceneKit holds a frame back until the ones before it have finished, so
        // putting several into one unsent command buffer would wait forever.
        var current = commands
        for (index, pose) in poses.enumerated() {
            if index > 0, let next = queue.makeCommandBuffer() { current = next }
            SCNTransaction.begin()
            SCNTransaction.disableActions = true
            rig.simdPosition = pose.position
            rig.simdOrientation = pose.rotation
            lid?.simdOrientation = simd_quatf(angle: pose.lid, axis: SIMD3(1, 0, 0))
            cameraNode.simdPosition = SIMD3(Float(stage.centerX), Float(-stage.distance), Float(stage.centerZ))
            camera.projectionTransform = Self.projection(stage: stage, zoom: zoom, near: camera.zNear, far: camera.zFar)
            screen.geometry?.firstMaterial?.emission.contents = screenView
            screen.geometry?.firstMaterial?.emission.intensity = CGFloat(pose.display)
            SCNTransaction.commit()
            SCNTransaction.flush()

            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = sampledTexture
            pass.colorAttachments[0].resolveTexture = colorTextures[index]
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .multisampleResolve
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            pass.depthAttachment.texture = depthTexture
            pass.depthAttachment.loadAction = .clear
            pass.depthAttachment.storeAction = .dontCare
            pass.depthAttachment.clearDepth = 1

            if isFirstAtThisSize, index == 0 {
                // SceneKit loads resources and shaders when it first needs them, and the first frame can come out wrong
                // while it does, so that frame is drawn over by the next one.
                renderer.prepare(scene, shouldAbortBlock: nil)
                renderer.render(atTime: 0, viewport: viewport, commandBuffer: current, passDescriptor: pass)
            }
            renderer.render(atTime: 0, viewport: viewport, commandBuffer: current, passDescriptor: pass)
            current.commit()
        }
        current.waitUntilCompleted()

        // Metal's first row is the top of the picture; Core Image's origin is the bottom.
        let flip = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -renderSize.height)
        let frames = colorTextures.prefix(poses.count).compactMap { CIImage(mtlTexture: $0, options: [.colorSpace: Self.linear])?.transformed(by: flip) }
        guard var drawn = frames.first else { return }
        if frames.count > 1 {
            // The matrix works on unpremultiplied color, so scaling alpha alone scales the whole premultiplied pixel.
            let share = CGFloat(1) / CGFloat(frames.count)
            let scaled = frames.map { $0.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: share)]) }
            drawn = scaled.dropFirst().reduce(scaled[0]) { $1.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: $0]) }
        }
        if renderSize != stage.canvas {
            let scale = stage.canvas.height / renderSize.height
            drawn = drawn.applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: scale, kCIInputAspectRatioKey: (stage.canvas.width / renderSize.width) / scale,
            ]).cropped(to: CGRect(origin: .zero, size: stage.canvas))
        }
        body(drawn)
    }
}

/// Stills of a device on their own, for pictures of the devices and for checking them.
public enum MockupStudio {
    /// The device at a moment of a motion on a transparent background. Without a picture, its screen shows a calm gradient.
    public static func still(deviceID: String, motionID: String? = nil, time: Double = 100, canvas: CGSize, padding: Double = 0,
                             screen: CGImage? = nil, library: MockupLibrary = .shared) -> CGImage? {
        guard let metal = MTLCreateSystemDefaultDevice(), let queue = metal.makeCommandQueue(),
              let device = library.device(id: deviceID), let url = library.modelURL(id: deviceID),
              let renderer = MockupRenderer(modelURL: url, exposure: device.exposure, glow: device.glow, device: metal, queue: queue),
              let motion = motionID.flatMap({ device.motion(id: $0) }) ?? device.defaultMotion else { return nil }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CIContext(mtlDevice: metal, options: [.workingColorSpace: space, .outputColorSpace: space])
        let stage = MockupStage.fit(device, canvas: canvas, padding: padding)
        let rect = stage.screenRect
        let longest = max(rect.width, rect.height) * 2
        let size = device.screenAspect >= 1
            ? CGSize(width: (longest / 2).rounded() * 2, height: (longest / device.screenAspect / 2).rounded() * 2)
            : CGSize(width: (longest * device.screenAspect / 2).rounded() * 2, height: (longest / 2).rounded() * 2)
        var picture: CIImage
        if let screen {
            let image = CIImage(cgImage: screen)
            let fill = max(size.width / image.extent.width, size.height / image.extent.height)
            let scaled = image.transformed(by: CGAffineTransform(scaleX: fill, y: fill))
            picture = scaled.transformed(by: CGAffineTransform(translationX: (size.width - scaled.extent.width) / 2, y: (size.height - scaled.extent.height) / 2))
        } else {
            let gradient = CIFilter(name: "CILinearGradient", parameters: [
                "inputPoint0": CIVector(x: 0, y: size.height), "inputPoint1": CIVector(x: size.width, y: 0),
                "inputColor0": CIColor(red: 0.28, green: 0.34, blue: 0.86), "inputColor1": CIColor(red: 0.62, green: 0.32, blue: 0.86)])!
            picture = gradient.outputImage!
        }
        picture = picture.cropped(to: CGRect(origin: .zero, size: size))
        var result: CGImage?
        renderer.render(picture: picture, pictureSize: size, context: context, stage: stage, poses: [motion.pose(at: time)], supersampling: MockupRenderer.supersampling(for: stage.canvas), zoom: .identity) { image in
            result = context.createCGImage(image, from: CGRect(origin: .zero, size: canvas), format: .RGBA8, colorSpace: space)
        }
        return result
    }
}
