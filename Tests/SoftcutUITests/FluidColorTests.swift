import SwiftUI
import XCTest
@testable import SoftcutUI

/// The color picker's model: every format reads from hue, saturation, value and alpha.
final class FluidColorTests: XCTestCase {
    func testHexRoundTrips() {
        for hex in ["6B97FF", "000000", "FFFFFF", "EF4444", "22C55E", "123456"] {
            let value = UInt32(hex, radix: 16)!
            let color = FluidHSVA(r: Double((value >> 16) & 0xFF) / 255, g: Double((value >> 8) & 0xFF) / 255, b: Double(value & 0xFF) / 255)
            XCTAssertEqual(color.hex, hex)
        }
    }

    func testAGrayKeepsTheHueItCameFrom() {
        // Dragging a blue into the gray or black edge of the square must not lose the hue.
        let gray = FluidHSVA(r: 0.5, g: 0.5, b: 0.5, keepingHue: 222)
        XCTAssertEqual(gray.h, 222)
        XCTAssertEqual(gray.s, 0)
        let black = FluidHSVA(r: 0, g: 0, b: 0, keepingHue: 40)
        XCTAssertEqual(black.h, 40)
    }

    func testHSLRoundTrips() {
        let start = FluidHSVA(h: 200, s: 0.6, v: 0.8)
        let hsl = start.hsl
        let back = FluidHSVA.fromHSL(h: hsl.h, s: hsl.s, l: hsl.l, a: 1)
        XCTAssertEqual(back.h, start.h, accuracy: 1e-9)
        XCTAssertEqual(back.s, start.s, accuracy: 1e-9)
        XCTAssertEqual(back.v, start.v, accuracy: 1e-9)
    }

    func testOKLCHRoundTripsAndMatchesKnownValues() {
        // Pure white is L 1, C 0; the focus blue lands where any OKLCH converter puts it.
        let white = FluidHSVA(r: 1, g: 1, b: 1).oklch
        XCTAssertEqual(white.l, 1, accuracy: 1e-3)
        XCTAssertEqual(white.c, 0, accuracy: 1e-3)

        let blue = FluidHSVA(r: 0x6B / 255.0, g: 0x97 / 255.0, b: 1)
        let ok = blue.oklch
        // Reference values from Ottosson's published OKLab code.
        XCTAssertEqual(ok.l, 0.6926, accuracy: 0.001)
        XCTAssertEqual(ok.c, 0.1606, accuracy: 0.001)
        XCTAssertEqual(ok.h, 265.19, accuracy: 0.1)
        let back = FluidHSVA.fromOKLCH(l: ok.l, c: ok.c, h: ok.h, a: 1, keepingHue: blue.h)
        XCTAssertEqual(back.hex, blue.hex)
    }
}
