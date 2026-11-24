import CoreGraphics
import CoreImage

/// Cursors drawn in code, for when a different look is wanted than the one that was on screen.
/// They are one shape each: the recorded cursor changes shape (arrow, hand, text), these do not.
enum CursorArt {
    struct Art {
        let image: CIImage
        let meta: CursorImage
        let pixelHeight: Double
    }

    private static let points = 28.0
    private static let scale = 8.0

    static func art(for style: CursorStyle) -> Art? {
        guard style != .system, style != .dark else { return nil }
        let pixels = Int(points * scale)
        guard let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Draw in points with the origin at the top-left, like the recorded cursors.
        ctx.translateBy(x: 0, y: CGFloat(pixels))
        ctx.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)

        let white = CGColor(gray: 1, alpha: 1)
        let ink = CGColor(gray: 0.05, alpha: 1)
        var hotspot = CGPoint(x: 3, y: 3)

        switch style {
        case .system, .dark:
            return nil
        case .arrow:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 3, y: 3))
            path.addLine(to: CGPoint(x: 3, y: 21))
            path.addLine(to: CGPoint(x: 7.4, y: 16.9))
            path.addLine(to: CGPoint(x: 10.6, y: 24))
            path.addLine(to: CGPoint(x: 13.6, y: 22.7))
            path.addLine(to: CGPoint(x: 10.4, y: 15.7))
            path.addLine(to: CGPoint(x: 16.4, y: 15.7))
            path.closeSubpath()
            // Black with a white outline, so it reads on light and dark screens alike.
            ctx.addPath(path)
            ctx.setFillColor(ink)
            ctx.setStrokeColor(white)
            ctx.setLineWidth(1.8)
            ctx.drawPath(using: .fillStroke)
        case .dot:
            hotspot = CGPoint(x: 14, y: 14)
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.92))
            ctx.fillEllipse(in: CGRect(x: 5, y: 5, width: 18, height: 18))
            ctx.setStrokeColor(CGColor(gray: 0.05, alpha: 0.55))
            ctx.setLineWidth(1.4)
            ctx.strokeEllipse(in: CGRect(x: 5, y: 5, width: 18, height: 18))
        case .ring:
            hotspot = CGPoint(x: 14, y: 14)
            ctx.setStrokeColor(CGColor(gray: 0.05, alpha: 0.6))
            ctx.setLineWidth(5.2)
            ctx.strokeEllipse(in: CGRect(x: 4.5, y: 4.5, width: 19, height: 19))
            ctx.setStrokeColor(white)
            ctx.setLineWidth(3)
            ctx.strokeEllipse(in: CGRect(x: 4.5, y: 4.5, width: 19, height: 19))
        case .crosshair:
            hotspot = CGPoint(x: 14, y: 14)
            for (color, width) in [(ink, 4.2), (white, 2.2)] as [(CGColor, Double)] {
                ctx.setStrokeColor(color)
                ctx.setLineWidth(width)
                ctx.move(to: CGPoint(x: 14, y: 4)); ctx.addLine(to: CGPoint(x: 14, y: 24))
                ctx.move(to: CGPoint(x: 4, y: 14)); ctx.addLine(to: CGPoint(x: 24, y: 14))
                ctx.strokePath()
            }
        }

        guard let image = ctx.makeImage() else { return nil }
        let meta = CursorImage(id: "style-\(style.rawValue)", file: "", hotspotX: hotspot.x, hotspotY: hotspot.y, width: points, height: points)
        return Art(image: CIImage(cgImage: image), meta: meta, pixelHeight: Double(pixels))
    }
}

// MARK: Dark cursors

extension CursorArt {
    /// A pixel of the picture, as 0...255 values with the color already multiplied by the alpha.
    private struct Raster {
        let width: Int
        let height: Int
        var bytes: [UInt8]

        init?(_ image: CGImage) {
            width = image.width
            height = image.height
            bytes = [UInt8](repeating: 0, count: width * height * 4)
            let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
                guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            if !drawn { return nil }
        }

        func alpha(_ x: Int, _ y: Int) -> Int {
            guard x >= 0, y >= 0, x < width, y < height else { return 0 }
            return Int(bytes[(y * width + x) * 4 + 3])
        }

        /// Brightness from 0 to 1 of a pixel that is opaque, or nil if it is not.
        func brightness(_ x: Int, _ y: Int) -> Double? {
            let offset = (y * width + x) * 4
            let a = Double(bytes[offset + 3])
            guard a > 0 else { return nil }
            return (0.299 * Double(bytes[offset]) + 0.587 * Double(bytes[offset + 1]) + 0.114 * Double(bytes[offset + 2])) / a
        }
    }

    /// How far each pixel is from the nearest transparent one, in steps. The deepest pixels are the heart of the fill.
    private static func depths(_ raster: Raster) -> [Int] {
        let width = raster.width, height = raster.height
        var depth = [Int](repeating: 0, count: width * height)
        let far = width + height
        for y in 0..<height {
            for x in 0..<width where raster.alpha(x, y) >= 128 { depth[y * width + x] = far }
        }
        // Two sweeps are enough to spread the distance in every direction.
        for y in 0..<height {
            for x in 0..<width where depth[y * width + x] > 0 {
                let left = x > 0 ? depth[y * width + x - 1] : 0
                let above = y > 0 ? depth[(y - 1) * width + x] : 0
                depth[y * width + x] = min(depth[y * width + x], left + 1, above + 1)
            }
        }
        for y in stride(from: height - 1, through: 0, by: -1) {
            for x in stride(from: width - 1, through: 0, by: -1) where depth[y * width + x] > 0 {
                let right = x < width - 1 ? depth[y * width + x + 1] : 0
                let below = y < height - 1 ? depth[(y + 1) * width + x] : 0
                depth[y * width + x] = min(depth[y * width + x], right + 1, below + 1)
            }
        }
        return depth
    }

    /// Whether a cursor picture is mostly light inside, like the white arrow macOS shows over a dark screen.
    /// Only the heart of the shape counts: the outline is the opposite color by design, and however thick it is,
    /// the deepest part of the shape is the fill.
    static func isLight(_ image: CGImage) -> Bool {
        guard let raster = Raster(image) else { return false }
        let depth = depths(raster)
        guard let deepest = depth.max(), deepest > 0 else { return false }
        let threshold = max(1, Int((Double(deepest) * 0.7).rounded(.down)))
        var sum = 0.0
        var count = 0
        for y in 0..<raster.height {
            for x in 0..<raster.width where depth[y * raster.width + x] >= threshold {
                if let value = raster.brightness(x, y) {
                    sum += value
                    count += 1
                }
            }
        }
        return count > 0 && sum / Double(count) > 0.5
    }

    /// The cursor picture made dark: black inside with a white outline. A picture that is already dark is left as it is.
    static func darkened(_ image: CGImage) -> CGImage {
        guard isLight(image), var raster = Raster(image) else { return image }
        // Flip the colors, keeping the transparency: a white arrow with a black outline becomes a black arrow with a white one.
        for index in stride(from: 0, to: raster.bytes.count, by: 4) {
            let a = raster.bytes[index + 3]
            guard a > 0 else { continue }
            for channel in 0..<3 { raster.bytes[index + channel] = a - raster.bytes[index + channel] }
        }
        let width = raster.width, height = raster.height
        return raster.bytes.withUnsafeMutableBytes { buffer -> CGImage? in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        } ?? image
    }
}
