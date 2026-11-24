import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Hides parts of a picture, for the finished video and for the stills the editor shows while placing a mask.
public enum MaskPainter {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// Blurs, pixelates or covers the regions that are hidden at this moment. Positions are in source pixels.
    static func apply(to image: CIImage, masks: [MaskRegion], time t: Double, size: (Double, Double)) -> CIImage {
        var result = image
        for mask in masks where !mask.isDisabled && t >= mask.start && t <= mask.end {
            let rect = CGRect(x: mask.rect.x * size.0, y: (1 - mask.rect.y - mask.rect.height) * size.1,
                              width: mask.rect.width * size.0, height: mask.rect.height * size.1).integral
            let hidden: CIImage
            switch mask.kind {
            case .blur:
                // Blurred from the picture around it too, so the edge of the region does not turn dark.
                hidden = result.clampedToExtent().applyingGaussianBlur(sigma: size.0 * (0.004 + 0.02 * mask.strength)).cropped(to: rect)
            case .pixelate:
                hidden = result.applyingFilter("CIPixellate", parameters: [kCIInputCenterKey: CIVector(x: rect.minX, y: rect.minY),
                                                                           kCIInputScaleKey: size.0 * (0.005 + 0.025 * mask.strength)]).cropped(to: rect)
            case .fill:
                hidden = CIImage(color: CIColor(red: 0.08, green: 0.08, blue: 0.09)).cropped(to: rect)
            }
            let edge = CIFilter.roundedRectangleGenerator()
            edge.extent = rect
            edge.radius = Float(min(rect.width, rect.height) * 0.08)
            edge.color = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
            result = hidden.applyingFilter("CIBlendWithAlphaMask", parameters: [
                kCIInputBackgroundImageKey: result,
                kCIInputMaskImageKey: edge.outputImage!,
            ])
        }
        return result
    }

    /// A still with the regions hidden at this moment hidden, exactly as the video will show them.
    public static func paint(_ image: CGImage, masks: [MaskRegion], time: Double) -> CGImage? {
        let source = CIImage(cgImage: image)
        let painted = apply(to: source, masks: masks, time: time, size: (Double(image.width), Double(image.height)))
        return context.createCGImage(painted, from: source.extent)
    }
}
