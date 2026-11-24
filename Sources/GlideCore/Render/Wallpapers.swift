import CoreImage
import CoreImage.CIFilterBuiltins

/// A background made of a base color with soft glows of other colors on it, plus a little film grain.
/// They are generated from these few numbers, so no image files are needed.
public struct Wallpaper: Identifiable, Sendable {
    public let id: String
    public let name: String
    let base: RGB
    let glows: [Glow]
    let grain: Double

    struct Glow: Sendable {
        /// Position as fractions of the canvas, measured from the top-left corner.
        let x: Double
        let y: Double
        /// Size as a fraction of the longer side of the canvas.
        let radius: Double
        let color: RGB
        let alpha: Double

        init(_ x: Double, _ y: Double, _ radius: Double, _ hex: UInt32, _ alpha: Double) {
            self.x = x
            self.y = y
            self.radius = radius
            self.color = RGB(hex: hex)
            self.alpha = alpha
        }
    }

    init(_ id: String, _ name: String, base: UInt32, grain: Double = 0.035, glows: [Glow]) {
        self.id = id
        self.name = name
        self.base = RGB(hex: base)
        self.glows = glows
        self.grain = grain
    }
}

public enum Wallpapers {
    public static let all: [Wallpaper] = [
        Wallpaper("nebula", "Nebula", base: 0x1B1038, glows: [.init(0.2, 0.2, 0.7, 0x6C3BFF, 0.9), .init(0.85, 0.25, 0.6, 0xFF4FA3, 0.75), .init(0.5, 0.95, 0.8, 0x2A6BFF, 0.8)]),
        Wallpaper("lagoon", "Lagoon", base: 0x063B4A, glows: [.init(0.15, 0.8, 0.7, 0x00D2C6, 0.85), .init(0.8, 0.2, 0.65, 0x1E90FF, 0.7), .init(0.6, 0.7, 0.5, 0x7CFFCB, 0.5)]),
        Wallpaper("ember", "Ember", base: 0x2B0A12, glows: [.init(0.8, 0.85, 0.8, 0xFF6B2C, 0.9), .init(0.2, 0.3, 0.6, 0xE5195E, 0.8), .init(0.55, 0.1, 0.5, 0xFFB347, 0.5)]),
        Wallpaper("meadow", "Meadow", base: 0x0E2E1C, glows: [.init(0.25, 0.75, 0.7, 0x4CD964, 0.8), .init(0.85, 0.3, 0.6, 0xB6E34B, 0.6), .init(0.5, 0.1, 0.5, 0x1FA97A, 0.7)]),
        Wallpaper("haze", "Dusk haze", base: 0x2A2140, glows: [.init(0.1, 0.9, 0.7, 0xFF8E72, 0.8), .init(0.9, 0.15, 0.7, 0x8E7CFF, 0.8), .init(0.5, 0.5, 0.5, 0xFFC1A1, 0.4)]),
        Wallpaper("glacier", "Glacier", base: 0xD7E9F5, grain: 0.02, glows: [.init(0.2, 0.25, 0.7, 0x8EC5FF, 0.8), .init(0.85, 0.8, 0.7, 0xBFD9FF, 0.8), .init(0.6, 0.4, 0.4, 0xFFFFFF, 0.6)]),
        Wallpaper("orchid", "Orchid", base: 0x2E0F3D, glows: [.init(0.8, 0.8, 0.8, 0xD946EF, 0.8), .init(0.15, 0.2, 0.6, 0x7C3AED, 0.8), .init(0.5, 0.55, 0.4, 0xFF9AD5, 0.4)]),
        Wallpaper("citrus", "Citrus", base: 0xFFF3C4, grain: 0.02, glows: [.init(0.15, 0.2, 0.7, 0xFFB400, 0.8), .init(0.85, 0.85, 0.7, 0xFF7A00, 0.7), .init(0.6, 0.2, 0.4, 0xFFE066, 0.8)]),
        Wallpaper("midnight", "Midnight", base: 0x050A18, glows: [.init(0.8, 0.2, 0.7, 0x1D3FBF, 0.7), .init(0.2, 0.85, 0.6, 0x0B7285, 0.6)]),
        Wallpaper("rosewood", "Rosewood", base: 0x3B1B1B, glows: [.init(0.2, 0.2, 0.7, 0xC2185B, 0.7), .init(0.85, 0.8, 0.7, 0xFF8A65, 0.7)]),
        Wallpaper("pearl", "Pearl", base: 0xF3EEF8, grain: 0.02, glows: [.init(0.2, 0.8, 0.7, 0xE8D5F5, 0.9), .init(0.8, 0.2, 0.7, 0xD0E6FF, 0.9), .init(0.5, 0.5, 0.5, 0xFFE5EC, 0.7)]),
        Wallpaper("volt", "Volt", base: 0x0B0F19, glows: [.init(0.15, 0.85, 0.7, 0x7CFF00, 0.55), .init(0.85, 0.15, 0.7, 0x00E5FF, 0.55)]),
    ]

    public static func wallpaper(id: String) -> Wallpaper { all.first { $0.id == id } ?? all[0] }

    /// The wallpaper as SVG text for a canvas of the given size: a base color and a soft radial glow for each of its colors.
    public static func svg(_ wallpaper: Wallpaper, size: CGSize) -> String {
        let width = Int(size.width.rounded()), height = Int(size.height.rounded())
        let longSide = max(size.width, size.height)
        func hex(_ rgb: RGB) -> String {
            func byte(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
            return String(format: "#%02X%02X%02X", byte(rgb.r), byte(rgb.g), byte(rgb.b))
        }
        var defs = ""
        var shapes = "<rect width=\"\(width)\" height=\"\(height)\" fill=\"\(hex(wallpaper.base))\"/>"
        for (index, glow) in wallpaper.glows.enumerated() {
            let color = hex(glow.color)
            defs += "<radialGradient id=\"g\(index)\" gradientUnits=\"userSpaceOnUse\" cx=\"\(Int(glow.x * size.width))\" cy=\"\(Int(glow.y * size.height))\" r=\"\(Int(glow.radius * longSide))\">"
                + "<stop offset=\"0\" stop-color=\"\(color)\" stop-opacity=\"\(glow.alpha)\"/>"
                + "<stop offset=\"1\" stop-color=\"\(color)\" stop-opacity=\"0\"/></radialGradient>"
            shapes += "<rect width=\"\(width)\" height=\"\(height)\" fill=\"url(#g\(index))\"/>"
        }
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(width)\" height=\"\(height)\" viewBox=\"0 0 \(width) \(height)\"><defs>\(defs)</defs>\(shapes)</svg>"
    }

    /// The wallpaper drawn to fill a canvas of the given size: its SVG, drawn at that size, with a little film grain on top.
    static func image(_ wallpaper: Wallpaper, canvas: CGSize) -> CIImage {
        let rect = CGRect(origin: .zero, size: canvas)
        guard let drawn = SVGRaster.cgImage(svg: Data(svg(wallpaper, size: canvas).utf8), size: canvas) else {
            return glowImage(wallpaper, canvas: canvas)
        }
        var image = CIImage(cgImage: drawn)
        if wallpaper.grain > 0, let noise = CIFilter.randomGenerator().outputImage {
            // Grey noise, faded to a whisper, so large flat areas do not band.
            let grey = noise.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])
                .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: wallpaper.grain)])
                .cropped(to: rect)
            image = grey.composited(over: image)
        }
        return image
    }

    /// The same picture built with Core Image, used if the SVG cannot be drawn.
    private static func glowImage(_ wallpaper: Wallpaper, canvas: CGSize) -> CIImage {
        let rect = CGRect(origin: .zero, size: canvas)
        let longSide = max(canvas.width, canvas.height)
        func color(_ rgb: RGB, alpha: Double = 1) -> CIColor { CIColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: alpha) }

        var image = CIImage(color: color(wallpaper.base)).cropped(to: rect)
        for glow in wallpaper.glows {
            let gradient = CIFilter.radialGradient()
            gradient.center = CGPoint(x: glow.x * canvas.width, y: (1 - glow.y) * canvas.height)
            gradient.radius0 = 0
            gradient.radius1 = Float(glow.radius * longSide)
            gradient.color0 = color(glow.color, alpha: glow.alpha)
            gradient.color1 = color(glow.color, alpha: 0)
            image = gradient.outputImage!.cropped(to: rect).composited(over: image)
        }

        if wallpaper.grain > 0, let noise = CIFilter.randomGenerator().outputImage {
            // Grey noise, faded to a whisper, so large flat areas do not band.
            let grey = noise.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])
                .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: wallpaper.grain)])
                .cropped(to: rect)
            image = grey.composited(over: image)
        }
        return image
    }

    private static let thumbnailContext = CIContext()

    /// A small picture of a wallpaper, for choosing between them.
    public static func thumbnail(id: String, size: CGSize) -> CGImage? {
        let picture = image(wallpaper(id: id), canvas: size)
        return thumbnailContext.createCGImage(picture, from: CGRect(origin: .zero, size: size))
    }
}
