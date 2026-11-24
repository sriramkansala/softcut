import AppKit

/// Draws SVG text to a bitmap at any size. SVG is a few hundred bytes of text for a picture that stays
/// sharp at 4K, which is why wallpapers are kept as SVG instead of image files.
enum SVGRaster {
    static func cgImage(svg data: Data, size: CGSize) -> CGImage? {
        guard size.width >= 1, size.height >= 1, let image = NSImage(data: data), image.isValid else { return nil }
        let width = Int(size.width.rounded()), height = Int(size.height.rounded())
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        // Draw the vector picture scaled to fill the bitmap, so it is rendered at this size and not stretched afterwards.
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.current = previous
        return ctx.makeImage()
    }

    static func cgImage(svgFile url: URL, size: CGSize) -> CGImage? {
        guard url.pathExtension.lowercased() == "svg", let data = try? Data(contentsOf: url) else { return nil }
        return cgImage(svg: data, size: size)
    }
}
