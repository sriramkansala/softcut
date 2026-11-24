import AppKit
import SwiftUI

// Fluid Functionalism's ColorPicker, ColorPickerPopover, ColorSwatch and ColorTile. Ported from the MIT-licensed
// originals by Micka Touillaud.

/// A color as hue, saturation, value and alpha: the model every format is read from, so the hue survives passing
/// through gray.
struct FluidHSVA: Equatable {
    var h: Double   // 0...360
    var s: Double   // 0...1
    var v: Double   // 0...1
    var a: Double = 1

    init(h: Double, s: Double, v: Double, a: Double = 1) {
        self.h = h; self.s = s; self.v = v; self.a = a
    }

    init(color: Color, keepingHue hue: Double? = nil) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(r: Double(ns.redComponent), g: Double(ns.greenComponent), b: Double(ns.blueComponent), a: Double(ns.alphaComponent), keepingHue: hue)
    }

    init(r: Double, g: Double, b: Double, a: Double = 1, keepingHue hue: Double? = nil) {
        let maxC = max(r, g, b), minC = min(r, g, b), delta = maxC - minC
        var h = 0.0
        if delta > 0 {
            if maxC == r { h = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
            else if maxC == g { h = 60 * ((b - r) / delta + 2) }
            else { h = 60 * ((r - g) / delta + 4) }
        }
        if h < 0 { h += 360 }
        let s = maxC == 0 ? 0 : delta / maxC
        // A color with no chroma keeps the hue it had, so dragging into gray or black never loses it.
        self.init(h: s == 0 ? (hue ?? 0) : h, s: s, v: maxC, a: a)
    }

    var rgb: (r: Double, g: Double, b: Double) {
        let c = v * s, x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1)), m = v - c
        let (r, g, b): (Double, Double, Double)
        switch h {
        case ..<60: (r, g, b) = (c, x, 0)
        case ..<120: (r, g, b) = (x, c, 0)
        case ..<180: (r, g, b) = (0, c, x)
        case ..<240: (r, g, b) = (0, x, c)
        case ..<300: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return (r + m, g + m, b + m)
    }

    var color: Color { let c = rgb; return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: a) }
    var opaque: Color { let c = rgb; return Color(.sRGB, red: c.r, green: c.g, blue: c.b) }

    var hex: String {
        let c = rgb
        return String(format: "%02X%02X%02X", Int((c.r * 255).rounded()), Int((c.g * 255).rounded()), Int((c.b * 255).rounded()))
    }

    var hsl: (h: Double, s: Double, l: Double) {
        let l = v * (1 - s / 2)
        let sl = (l == 0 || l == 1) ? 0 : (v - l) / min(l, 1 - l)
        return (h, sl, l)
    }

    static func fromHSL(h: Double, s: Double, l: Double, a: Double) -> FluidHSVA {
        let v = l + s * min(l, 1 - l)
        return FluidHSVA(h: h, s: v == 0 ? 0 : 2 * (1 - l / v), v: v, a: a)
    }

    /// OKLCH from Ottosson's matrices on linear sRGB.
    var oklch: (l: Double, c: Double, h: Double) {
        func linear(_ x: Double) -> Double { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        let c = rgb
        let (r, g, b) = (linear(c.r), linear(c.g), linear(c.b))
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        var hue = atan2(B, A) * 180 / .pi
        if hue < 0 { hue += 360 }
        return (L, sqrt(A * A + B * B), hue)
    }

    static func fromOKLCH(l L: Double, c C: Double, h H: Double, a: Double, keepingHue: Double) -> FluidHSVA {
        let A = C * cos(H * .pi / 180), B = C * sin(H * .pi / 180)
        let l = pow(L + 0.3963377774 * A + 0.2158037573 * B, 3)
        let m = pow(L - 0.1055613458 * A - 0.0638541728 * B, 3)
        let s = pow(L - 0.0894841775 * A - 1.2914855480 * B, 3)
        func gamma(_ x: Double) -> Double { let x = min(max(x, 0), 1); return x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055 }
        let r = gamma(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s)
        let g = gamma(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s)
        let b = gamma(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
        return FluidHSVA(r: r, g: g, b: b, a: a, keepingHue: keepingHue)
    }
}

/// The checkerboard behind see-through colors: 4 pt squares.
struct FluidChecker: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(fluidHex: 0x2A2A2A)))
            var dark = Path()
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = row % 2 == 0 ? 4 : 0
                while x < size.width {
                    dark.addRect(CGRect(x: x, y: y, width: 4, height: 4))
                    x += 8
                }
                y += 4
                row += 1
            }
            context.fill(dark, with: .color(Color(fluidHex: 0x1F1F1F)))
        }
    }
}

/// A small, non-interactive patch of a color over the checkerboard.
struct FluidColorTile: View {
    let color: Color
    var size: CGFloat = 24

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: min(Fluid.Radius.item, size / 3), style: .continuous)
        ZStack { FluidChecker(); color }
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color(white: 0.5, opacity: 0.25), lineWidth: 1))
    }
}

enum FluidColorFormat: String, CaseIterable {
    case hex = "HEX", rgb = "RGB", hsl = "HSL", oklch = "OKLCH"
}

/// The full picker: a saturation and brightness square, hue (and alpha) rails, a format menu and the eyedropper,
/// channel fields that can be typed in or dragged, and swatches.
struct FluidColorPicker: View {
    @Binding var color: Color
    var showsAlpha = false
    var swatches: [Color] = []

    @State private var hsva = FluidHSVA(h: 222, s: 0.58, v: 1)
    @State private var format = FluidColorFormat.hex
    @State private var lastWritten: Color?
    @State private var areaHover: CGPoint?
    @State private var formatOpen = false

    private let width: CGFloat = 256

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            saturationArea
            VStack(spacing: -1) {
                FluidColorRail(value: Binding(get: { hsva.h }, set: { hsva.h = $0; write() }), range: 0...360,
                               knob: FluidHSVA(h: hsva.h, s: 1, v: 1).opaque, label: "Hue", format: { "\(Int($0))°" }) {
                    LinearGradient(colors: stride(from: 0.0, through: 360, by: 60).map { FluidHSVA(h: $0 == 360 ? 359.9 : $0, s: 1, v: 1).opaque },
                                   startPoint: .leading, endPoint: .trailing)
                }
                if showsAlpha {
                    FluidColorRail(value: Binding(get: { hsva.a * 100 }, set: { hsva.a = $0 / 100; write() }), range: 0...100,
                                   knob: hsva.opaque, label: "Alpha", format: { "\(Int($0))%" }) {
                        ZStack {
                            FluidChecker()
                            LinearGradient(colors: [hsva.opaque.opacity(0), hsva.opaque], startPoint: .leading, endPoint: .trailing)
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                FluidDropdown(rows: {
                    FluidColorFormat.allCases.map { f in .item(f.rawValue, checked: f == format) { format = f } }
                }, width: 124) { open in
                    HStack {
                        Text(format.rawValue).font(Fluid.font(.body, density: .compact))
                        Spacer()
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .medium))
                            .rotationEffect(.degrees(open ? 180 : 0))
                            .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.15), value: open)
                    }
                    .foregroundStyle(open ? Fluid.foreground : Fluid.mutedForeground)
                    .padding(.horizontal, 10)
                    .frame(width: 124, height: 28)
                    .background(open ? Fluid.active : .clear, in: RoundedRectangle(cornerRadius: Fluid.Radius.item))
                    .fluidHoverFill()
                }
                Button {
                    NSColorSampler().show { picked in
                        guard let picked = picked?.usingColorSpace(.sRGB) else { return }
                        Task { @MainActor in
                            hsva = FluidHSVA(r: Double(picked.redComponent), g: Double(picked.greenComponent), b: Double(picked.blueComponent),
                                             a: hsva.a, keepingHue: hsva.h)
                            write()
                        }
                    }
                } label: {
                    Image(systemName: "eyedropper").font(.system(size: 13))
                        .frame(width: 124, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(FluidButtonStyle(variant: .ghost, size: .compact))
                .fluidTooltip("Pick a color from the screen")
            }
            channelFields
            if !swatches.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 8), count: 7), alignment: .leading, spacing: 8) {
                    ForEach(Array(swatches.enumerated()), id: \.offset) { _, swatch in
                        FluidColorSwatch(color: swatch, isSelected: FluidHSVA(color: swatch).hex == hsva.hex) {
                            hsva = FluidHSVA(color: swatch, keepingHue: hsva.h)
                            write()
                        }
                    }
                }
            }
        }
        .frame(width: width)
        .padding(12)
        .onAppear { hsva = FluidHSVA(color: color) }
        .onChange(of: color) { _, new in
            // Only colors that come from outside replace the model, so the hue held through grays isn't lost.
            if new != lastWritten { hsva = FluidHSVA(color: new, keepingHue: hsva.h) }
        }
    }

    private func write() {
        let new = hsva.color
        lastWritten = new
        color = new
    }

    // MARK: Square

    private var saturationArea: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [.white, FluidHSVA(h: hsva.h, s: 1, v: 1).opaque], startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                if let areaHover {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.55), lineWidth: 2)
                        .background(Circle().stroke(Color.black.opacity(0.2), lineWidth: 1).padding(-0.5))
                        .frame(width: 18, height: 18)
                        .position(areaHover)
                        .allowsHitTesting(false)
                }
                Circle()
                    .fill(hsva.opaque)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 1))
                    .overlay(Circle().stroke(.black, lineWidth: 1).padding(-0.5))
                    .frame(width: 18, height: 18)
                    .position(x: hsva.s * size.width, y: (1 - hsva.v) * size.height)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): areaHover = point
                case .ended: areaHover = nil
                }
            }
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                areaHover = nil
                hsva.s = min(max(drag.location.x / size.width, 0), 1)
                hsva.v = 1 - min(max(drag.location.y / size.height, 0), 1)
                write()
            })
            .onHover { inside in if inside { NSCursor.hide() } else { NSCursor.unhide() } }
        }
        .frame(height: 156)
        .accessibilityElement()
        .accessibilityLabel("Saturation and brightness")
        .accessibilityAdjustableAction { direction in
            hsva.v = min(max(hsva.v + (direction == .increment ? 0.01 : -0.01), 0), 1)
            write()
        }
    }

    // MARK: Channels

    @ViewBuilder
    private var channelFields: some View {
        switch format {
        case .hex:
            HStack(spacing: 8) {
                FluidHexField(hex: hsva.hex) { text in
                    var value: UInt64 = 0
                    guard Scanner(string: text).scanHexInt64(&value) else { return }
                    let digits = text.count
                    let rgb: (Double, Double, Double)
                    if digits == 3 {
                        rgb = (Double((value >> 8) & 0xF) / 15, Double((value >> 4) & 0xF) / 15, Double(value & 0xF) / 15)
                    } else if digits == 6 {
                        rgb = (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
                    } else { return }
                    hsva = FluidHSVA(r: rgb.0, g: rgb.1, b: rgb.2, a: hsva.a, keepingHue: hsva.h)
                    write()
                }
                if showsAlpha { alphaField }
            }
        case .rgb:
            let c = hsva.rgb
            HStack(spacing: 4) {
                FluidScrubField(label: "Red", value: c.r * 255, range: 0...255) { set(r: $0 / 255) }
                FluidScrubField(label: "Green", value: c.g * 255, range: 0...255) { set(g: $0 / 255) }
                FluidScrubField(label: "Blue", value: c.b * 255, range: 0...255) { set(b: $0 / 255) }
                if showsAlpha { alphaField }
            }
        case .hsl:
            let hsl = hsva.hsl
            HStack(spacing: 4) {
                FluidScrubField(label: "Hue", value: hsl.h, range: 0...360, wraps: true) {
                    hsva = .fromHSL(h: $0, s: hsl.s, l: hsl.l, a: hsva.a); write()
                }
                FluidScrubField(label: "Saturation", value: hsl.s * 100, range: 0...100) {
                    hsva = .fromHSL(h: hsl.h, s: $0 / 100, l: hsl.l, a: hsva.a); write()
                }
                FluidScrubField(label: "Lightness", value: hsl.l * 100, range: 0...100) {
                    hsva = .fromHSL(h: hsl.h, s: hsl.s, l: $0 / 100, a: hsva.a); write()
                }
                if showsAlpha { alphaField }
            }
        case .oklch:
            let ok = hsva.oklch
            HStack(spacing: 4) {
                FluidScrubField(label: "Lightness", value: ok.l * 100, range: 0...100) {
                    hsva = .fromOKLCH(l: $0 / 100, c: ok.c, h: ok.h, a: hsva.a, keepingHue: hsva.h); write()
                }
                FluidScrubField(label: "Chroma", value: ok.c, range: 0...0.4, step: 0.01, decimals: 2) {
                    hsva = .fromOKLCH(l: ok.l, c: $0, h: ok.h, a: hsva.a, keepingHue: hsva.h); write()
                }
                FluidScrubField(label: "Hue", value: ok.h, range: 0...360, wraps: true) {
                    hsva = .fromOKLCH(l: ok.l, c: ok.c, h: $0, a: hsva.a, keepingHue: hsva.h); write()
                }
                if showsAlpha { alphaField }
            }
        }
    }

    private var alphaField: some View {
        FluidScrubField(label: "Alpha", value: hsva.a * 100, range: 0...100, suffix: "%") { hsva.a = $0 / 100; write() }
    }

    private func set(r: Double? = nil, g: Double? = nil, b: Double? = nil) {
        let c = hsva.rgb
        hsva = FluidHSVA(r: r ?? c.r, g: g ?? c.g, b: b ?? c.b, a: hsva.a, keepingHue: hsva.h)
        write()
    }
}

private extension View {
    /// The ghost hover fill used by the picker's own triggers.
    func fluidHoverFill() -> some View { modifier(FluidHoverFill()) }
}

private struct FluidHoverFill: ViewModifier {
    @State private var hovered = false
    func body(content: Content) -> some View {
        content
            .background(hovered ? Fluid.hover : .clear, in: RoundedRectangle(cornerRadius: Fluid.Radius.item))
            .foregroundStyle(hovered ? Fluid.foreground : Fluid.mutedForeground)
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.08), value: hovered)
    }
}

/// A gradient rail with a white-ringed knob, Fluid's compact slider without a fill.
private struct FluidColorRail<Track: View>: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let knob: Color
    let label: String
    let format: (Double) -> String
    @ViewBuilder var track: Track

    @State private var hoverX: CGFloat?
    @State private var dragging = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let usable = width - 20
            let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            ZStack(alignment: .topLeading) {
                track
                    .frame(width: width - 2, height: 18)
                    .clipShape(Capsule())
                    .offset(x: 1, y: 9)
                Circle()
                    .fill(knob)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
                    .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
                    .frame(width: 16, height: 16)
                    .frame(width: 20, height: 20)
                    .offset(x: CGFloat(fraction) * usable, y: 8)
                    .animation(dragging ? nil : Fluid.Motion.moderate, value: fraction)
                if let hoverX, !dragging {
                    let f = min(max((hoverX - 10) / usable, 0), 1)
                    FluidValueTip(text: format(range.lowerBound + Double(f) * (range.upperBound - range.lowerBound)))
                        .fixedSize()
                        .position(x: 10 + f * usable, y: -6)
                }
            }
            .frame(width: width, height: 36, alignment: .topLeading)
            .contentShape(Rectangle().inset(by: -8))
            .onContinuousHover { phase in
                if case .active(let p) = phase { hoverX = p.x } else { hoverX = nil }
            }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let f = Double(min(max((drag.location.x - 10) / usable, 0), 1))
                    let new = (range.lowerBound + f * (range.upperBound - range.lowerBound)).rounded()
                    if !dragging { withAnimation(Fluid.Motion.moderate) { value = new } } else { value = new }
                    dragging = true
                }
                .onEnded { _ in dragging = false })
        }
        .frame(height: 36)
        .accessibilityRepresentation { Slider(value: $value, in: range, step: 1) { Text(label) } }
    }
}

/// A number that can be dragged sideways to change it (one step per point) or clicked to type a new one.
struct FluidScrubField: View {
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var decimals = 0
    var wraps = false
    var suffix = ""
    let commit: (Double) -> Void

    @State private var editing = false
    @State private var text = ""
    @State private var dragStart: Double?
    @State private var hovered = false
    @FocusState private var focused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Fluid.Radius.item, style: .continuous)
        ZStack {
            if editing {
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .focused($focused)
                    .onSubmit(finish)
                    .onExitCommand { editing = false }
                    .onChange(of: focused) { _, now in if !now { finish() } }
            } else {
                Text(display(value) + suffix)
                    .frame(maxWidth: .infinity)
            }
        }
        .font(Fluid.font(.body, density: .compact, monospacedDigits: true))
        .foregroundStyle(Fluid.foreground)
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(dragStart != nil ? Fluid.active : (hovered ? Fluid.hover : .clear), in: shape)
        .overlay { if editing { shape.strokeBorder(Fluid.focusRing, lineWidth: 1) } }
        .contentShape(shape)
        .onHover { inside in
            hovered = inside
            if inside && !editing { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        }
        .gesture(editing ? nil : DragGesture(minimumDistance: 0)
            .onChanged { drag in
                if dragStart == nil { dragStart = value }
                guard abs(drag.translation.width) >= 1 else { return }
                commit(clamp((dragStart ?? value) + (drag.translation.width).rounded() * step))
            }
            .onEnded { drag in
                defer { dragStart = nil }
                // A press without a drag edits the number.
                if abs(drag.translation.width) < 1 {
                    text = display(value)
                    editing = true
                    DispatchQueue.main.async { focused = true }
                }
            })
        .fluidTooltip(label)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(display(value) + suffix)
        .accessibilityAdjustableAction { direction in commit(clamp(value + (direction == .increment ? step : -step))) }
    }

    private func display(_ number: Double) -> String { String(format: "%.\(decimals)f", number) }

    private func clamp(_ number: Double) -> Double {
        if wraps {
            let span = range.upperBound - range.lowerBound
            var wrapped = (number - range.lowerBound).truncatingRemainder(dividingBy: span)
            if wrapped < 0 { wrapped += span }
            return range.lowerBound + wrapped
        }
        return min(max(number, range.lowerBound), range.upperBound)
    }

    private func finish() {
        guard editing else { return }
        editing = false
        if let number = Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: suffix, with: "")) {
            commit(clamp(number))
        }
    }
}

/// The hex field: "#" then the six digits, typed and committed on Return or when it loses focus.
private struct FluidHexField: View {
    let hex: String
    let commit: (String) -> Void
    @State private var draft = ""
    @State private var hovered = false
    @FocusState private var focused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Fluid.Radius.item, style: .continuous)
        HStack(spacing: 4) {
            Text("#").font(Fluid.font(.caption, density: .compact)).foregroundStyle(Fluid.mutedForeground)
            TextField("", text: $draft)
                .textFieldStyle(.plain)
                .font(Fluid.font(.body, density: .compact, monospacedDigits: true))
                .foregroundStyle(Fluid.foreground)
                .focused($focused)
                .onSubmit { commit(draft.trimmingCharacters(in: CharacterSet(charactersIn: "# "))); focused = false }
                .onExitCommand { draft = hex; focused = false }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(hovered && !focused ? Fluid.hover : .clear, in: shape)
        .overlay { if focused { shape.strokeBorder(Fluid.focusRing, lineWidth: 1) } }
        .onHover { hovered = $0 }
        .onAppear { draft = hex }
        .onChange(of: hex) { _, new in if !focused { draft = new } }
        .onChange(of: focused) { _, now in
            if !now { commit(draft.trimmingCharacters(in: CharacterSet(charactersIn: "# "))) }
        }
        .fluidTooltip("Hex")
    }
}

/// A preset color to click: ringed in gray under the pointer and in the focus blue when it is the current color.
struct FluidColorSwatch: View {
    let color: Color
    var isSelected = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Fluid.Radius.item, style: .continuous)
        Button(action: action) {
            ZStack { FluidChecker(); color }
                .frame(width: 28, height: 28)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color(white: 0.5, opacity: 0.25), lineWidth: 1))
                .overlay {
                    if isSelected || hovered {
                        RoundedRectangle(cornerRadius: Fluid.Radius.item + 4, style: .continuous)
                            .strokeBorder(isSelected ? Fluid.focusRing : Color(white: 0.5, opacity: 0.4), lineWidth: 2)
                            .padding(-4)
                    }
                }
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.1), value: hovered)
        .accessibilityLabel("Select color \(FluidHSVA(color: color).hex)")
    }
}

/// A bordered button showing the color and its hex value that opens the picker in a popup.
struct FluidColorWell: View {
    var label: String?
    @Binding var color: Color
    var showsAlpha = false
    var swatches: [Color] = FluidColorWell.defaultSwatches

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.fluidSurfaceLevel) private var substrate
    @State private var open = false
    @State private var hovered = false

    static let defaultSwatches: [Color] = [0xFFFFFF, 0x0A0A0A, 0xEF4444, 0xF97316, 0xFACC15, 0x22C55E, 0x14B8A6,
                                           0x3B82F6, 0x6366F1, 0x8B5CF6, 0xEC4899, 0xF43F5E, 0x737373, 0x6B97FF]
        .map { Color(fluidHex: $0) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Fluid.Radius.item, style: .continuous)
        Button { open.toggle() } label: {
            HStack(spacing: 6) {
                if let label {
                    Text(label).font(Fluid.font(.body, density: .compact)).foregroundStyle(Fluid.mutedForeground).padding(.horizontal, 4)
                }
                FluidColorTile(color: color, size: 16)
                Text(FluidHSVA(color: color).hex)
                    .font(Fluid.font(.body, density: .compact, monospacedDigits: true))
                    .foregroundStyle(Fluid.foreground)
            }
            .padding(.horizontal, 6)
            .frame(height: 28)
            .background(hovered || open ? Fluid.hover : .clear, in: shape)
            .overlay(shape.strokeBorder(Fluid.border, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovered = $0 && isEnabled }
        .opacity(isEnabled ? 1 : 0.5)
        .fluidPopup(isPresented: $open) {
            FluidPopupSurface(padding: 0, maxHeight: 600, substrate: substrate) {
                FluidColorPicker(color: $color, showsAlpha: showsAlpha, swatches: swatches)
            }
        }
        .accessibilityLabel(label ?? "Color")
        .accessibilityValue(FluidHSVA(color: color).hex)
    }
}
