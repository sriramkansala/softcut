import CoreGraphics
import CoreImage

/// Where things go when the screen is shown inside a device.
struct DeviceGeometry {
    /// Where the picture of the screen is drawn.
    var content: CGRect
    /// The picture is clipped to this rounded rectangle.
    var maskRect: CGRect
    var maskRadius: Double
    /// The outline of the whole device, which casts the shadow.
    var shadowRect: CGRect
    var shadowRadius: Double
}

/// Simple frames drawn in code: a browser window, a laptop and a monitor. Sizes are fractions of the
/// width of the screen picture, so a frame looks the same at any resolution.
enum DeviceFrames {
    private static func rounded(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX.rounded(), y: rect.minY.rounded(), width: rect.width.rounded(), height: rect.height.rounded())
    }

    // Proportions, relative to the width `w` of the screen picture.
    private static let browserBar = 0.05
    private static let laptopSide = 0.022, laptopChin = 0.035, laptopBase = 0.03, laptopBaseOverhang = 1.1
    private static let monitorSide = 0.016, monitorChin = 0.05, monitorNeck = 0.09, monitorBase = 0.016

    static func geometry(_ frame: DeviceFrame, available a: CGRect, screenAspect: Double,
                         cornerRadius: Double, canvasWidth: Double) -> DeviceGeometry {
        switch frame {
        case .none:
            let w = min(a.width, a.height * screenAspect)
            let h = w / screenAspect
            let content = rounded(CGRect(x: a.midX - w / 2, y: a.midY - h / 2, width: w, height: h))
            return DeviceGeometry(content: content, maskRect: content, maskRadius: cornerRadius,
                                  shadowRect: content, shadowRadius: cornerRadius)

        case .browser:
            let w = min(a.width, a.height / (1 / screenAspect + browserBar))
            let h = w / screenAspect
            let bar = w * browserBar
            let outer = rounded(CGRect(x: a.midX - w / 2, y: a.midY - (h + bar) / 2, width: w, height: h + bar))
            let content = CGRect(x: outer.minX, y: outer.minY, width: outer.width, height: outer.height - bar.rounded())
            return DeviceGeometry(content: content, maskRect: outer, maskRadius: cornerRadius,
                                  shadowRect: outer, shadowRadius: cornerRadius)

        case .laptop:
            let w = min(a.width / (laptopBaseOverhang * (1 + 2 * laptopSide)),
                        a.height / (1 / screenAspect + laptopSide + laptopChin + laptopBase))
            let h = w / screenAspect
            let side = w * laptopSide, chin = w * laptopChin, baseHeight = w * laptopBase
            let screenWidth = w + 2 * side
            let baseWidth = screenWidth * laptopBaseOverhang
            let totalHeight = h + side + chin + baseHeight
            let bottom = a.midY - totalHeight / 2
            let screenOuter = rounded(CGRect(x: a.midX - screenWidth / 2, y: bottom + baseHeight, width: screenWidth, height: h + side + chin))
            let content = rounded(CGRect(x: screenOuter.minX + side, y: screenOuter.minY + chin, width: w, height: h))
            let base = CGRect(x: a.midX - baseWidth / 2, y: bottom, width: baseWidth, height: baseHeight)
            return DeviceGeometry(content: content, maskRect: content, maskRadius: 0.004 * canvasWidth,
                                  shadowRect: rounded(screenOuter.union(base)), shadowRadius: w * 0.02)

        case .monitor:
            let w = min(a.width / (1 + 2 * monitorSide),
                        a.height / (1 / screenAspect + monitorSide + monitorChin + monitorNeck + monitorBase))
            let h = w / screenAspect
            let side = w * monitorSide, chin = w * monitorChin, neck = w * monitorNeck, baseHeight = w * monitorBase
            let screenWidth = w + 2 * side
            let totalHeight = h + side + chin + neck + baseHeight
            let bottom = a.midY - totalHeight / 2
            let screenOuter = rounded(CGRect(x: a.midX - screenWidth / 2, y: bottom + baseHeight + neck, width: screenWidth, height: h + side + chin))
            let content = rounded(CGRect(x: screenOuter.minX + side, y: screenOuter.minY + chin, width: w, height: h))
            let baseWidth = w * 0.34
            let base = CGRect(x: a.midX - baseWidth / 2, y: bottom, width: baseWidth, height: baseHeight + neck)
            return DeviceGeometry(content: content, maskRect: content, maskRadius: 0.003 * canvasWidth,
                                  shadowRect: rounded(screenOuter.union(base)), shadowRadius: w * 0.02)
        }
    }

    /// The parts of the device around the picture, drawn on a transparent canvas.
    static func art(_ frame: DeviceFrame, geometry g: DeviceGeometry, canvas: CGSize) -> CIImage? {
        guard frame != .none,
              let ctx = CGContext(data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        let w = g.content.width
        func fill(_ rect: CGRect, radius: Double, hex: UInt32, alpha: Double = 1) {
            ctx.setFillColor(CGColor(srgbRed: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255,
                                     blue: Double(hex & 0xff) / 255, alpha: alpha))
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: min(radius, rect.width / 2), cornerHeight: min(radius, rect.height / 2), transform: nil))
            ctx.fillPath()
        }

        switch frame {
        case .none:
            return nil

        case .browser:
            let outer = g.maskRect
            let bar = CGRect(x: outer.minX, y: g.content.maxY, width: outer.width, height: outer.maxY - g.content.maxY)
            // The bar, rounded at the top only: a rounded rectangle taller than the bar, cut off below it.
            ctx.saveGState()
            ctx.clip(to: bar)
            fill(CGRect(x: outer.minX, y: bar.minY - bar.height, width: outer.width, height: bar.height * 2), radius: g.maskRadius, hex: 0xECECEF)
            ctx.restoreGState()
            fill(CGRect(x: bar.minX, y: bar.minY, width: bar.width, height: max(1, bar.height * 0.03)), radius: 0, hex: 0xD2D2D8)

            // Traffic lights and an address field.
            let dot = bar.height * 0.3
            for (index, hex) in [UInt32(0xFF5F57), 0xFEBC2E, 0x28C840].enumerated() {
                let x = bar.minX + bar.height * 0.5 + Double(index) * dot * 1.9
                ctx.setFillColor(CGColor(srgbRed: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255,
                                         blue: Double(hex & 0xff) / 255, alpha: 1))
                ctx.fillEllipse(in: CGRect(x: x, y: bar.midY - dot / 2, width: dot, height: dot))
            }
            let fieldWidth = bar.width * 0.46, fieldHeight = bar.height * 0.56
            let field = CGRect(x: bar.midX - fieldWidth / 2, y: bar.midY - fieldHeight / 2, width: fieldWidth, height: fieldHeight)
            fill(field, radius: fieldHeight / 2, hex: 0xFFFFFF, alpha: 0.95)
            fill(CGRect(x: field.minX + fieldHeight * 0.4, y: field.midY - fieldHeight * 0.14, width: fieldHeight * 0.28, height: fieldHeight * 0.28),
                 radius: fieldHeight, hex: 0xB4B4BC)
            fill(CGRect(x: field.minX + fieldHeight * 0.95, y: field.midY - fieldHeight * 0.09, width: field.width * 0.32, height: fieldHeight * 0.18),
                 radius: fieldHeight, hex: 0xD0D0D6)

        case .laptop:
            let side = w * laptopSide, chin = w * laptopChin
            let screenOuter = CGRect(x: g.content.minX - side, y: g.content.minY - chin, width: w + 2 * side, height: g.content.height + side + chin)
            let baseHeight = w * laptopBase
            let baseWidth = screenOuter.width * laptopBaseOverhang
            let base = CGRect(x: screenOuter.midX - baseWidth / 2, y: screenOuter.minY - baseHeight, width: baseWidth, height: baseHeight)
            fill(base, radius: baseHeight * 0.9, hex: 0xB9BDC5)
            fill(CGRect(x: base.minX, y: base.midY, width: base.width, height: base.height / 2), radius: 0, hex: 0xD6D9DE)
            fill(CGRect(x: base.midX - base.width * 0.09, y: base.maxY - baseHeight * 0.45, width: base.width * 0.18, height: baseHeight * 0.45),
                 radius: baseHeight * 0.3, hex: 0x9EA3AC)
            fill(screenOuter, radius: w * 0.03, hex: 0x0C0C0E)
            // Camera dot in the top bezel.
            let dot = side * 0.34
            ctx.setFillColor(CGColor(srgbRed: 0.16, green: 0.16, blue: 0.19, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: screenOuter.midX - dot / 2, y: screenOuter.maxY - side / 2 - dot / 2, width: dot, height: dot))

        case .monitor:
            let side = w * monitorSide, chin = w * monitorChin, neck = w * monitorNeck, baseHeight = w * monitorBase
            let screenOuter = CGRect(x: g.content.minX - side, y: g.content.minY - chin, width: w + 2 * side, height: g.content.height + side + chin)
            let neckRect = CGRect(x: screenOuter.midX - w * 0.07, y: screenOuter.minY - neck, width: w * 0.14, height: neck + 2)
            fill(neckRect, radius: 0, hex: 0xB3B7BF)
            let base = CGRect(x: screenOuter.midX - w * 0.17, y: neckRect.minY - baseHeight, width: w * 0.34, height: baseHeight)
            fill(base, radius: baseHeight * 0.5, hex: 0xA2A7AF)
            fill(screenOuter, radius: w * 0.018, hex: 0x17171A)
            // A small mark on the chin.
            ctx.setFillColor(CGColor(gray: 0.45, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: screenOuter.midX - chin * 0.09, y: screenOuter.minY + chin * 0.4, width: chin * 0.18, height: chin * 0.18))
        }

        return ctx.makeImage().map { CIImage(cgImage: $0) }
    }
}
