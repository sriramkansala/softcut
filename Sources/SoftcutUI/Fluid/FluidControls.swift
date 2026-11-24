import SwiftUI

// Fluid Functionalism's basic controls in SwiftUI: Button, Switch and Slider (both of its engines).
// Ported from the MIT-licensed originals by Micka Touillaud (reference/fluid-registry).

// MARK: Button

enum FluidButtonVariant {
    /// A light fill with dark text: the one main action on a surface.
    case primary
    /// A see-through tint that takes on the surface under it.
    case secondary
    /// Outlined.
    case tertiary
    /// Text only until hovered.
    case ghost
    /// Softcut's one brand action (Export): a purple gradient with a soft top highlight.
    case accent
    /// A dark filled button with a hairline border, for strong secondary actions beside `accent`.
    case raised
}

enum FluidButtonSize {
    case regular, compact, icon, iconCompact

    var height: CGFloat {
        switch self {
        case .regular, .icon: return 36
        case .compact, .iconCompact: return 28
        }
    }
    var isIconOnly: Bool { self == .icon || self == .iconCompact }
    var isCompact: Bool { self == .compact || self == .iconCompact }
    var iconSize: CGFloat { isCompact ? 14 : 16 }
    var fontSize: CGFloat { isCompact ? 12 : 13 }
    var paddingX: CGFloat { isCompact ? 12 : 16 }
    /// An icon sits 4 pt closer to its edge than text does.
    var iconEdgePadding: CGFloat { isCompact ? 8 : 12 }
    var gap: CGFloat { isCompact ? 4 : 6 }
}

struct FluidButtonStyle: ButtonStyle {
    var variant: FluidButtonVariant = .primary
    var size: FluidButtonSize = .compact
    /// Draws the button as held, for one that has a popup open.
    var active = false
    var leadingIcon = false
    var trailingIcon = false
    /// Stretches the button across the space it is given, its label centred.
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        FluidButtonBody(configuration: configuration, style: self)
    }
}

private struct FluidButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let style: FluidButtonStyle
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @State private var hovered = false

    var body: some View {
        let pressed = configuration.isPressed
        let size = style.size
        let shape = RoundedRectangle(cornerRadius: Fluid.Radius.item, style: .continuous)
        configuration.label
            .font(.system(size: size.fontSize))
            .fontWeight(labelWeight)
            .foregroundStyle(textColor)
            .lineLimit(1)
            .fixedSize()
            .padding(.leading, size.isIconOnly ? 0 : (style.leadingIcon ? size.iconEdgePadding : size.paddingX))
            .padding(.trailing, size.isIconOnly ? 0 : (style.trailingIcon ? size.iconEdgePadding : size.paddingX))
            .frame(minWidth: size.isIconOnly ? size.height : nil, maxWidth: style.fullWidth ? .infinity : nil)
            .frame(height: size.height)
            .background {
                // Pressing pulls the surface in by exactly 1 pt per side at any width (a scale would warp).
                ZStack {
                    switch style.variant {
                    case .accent:
                        shape.fill(LinearGradient(colors: [Brand.light, Brand.deep], startPoint: .top, endPoint: .bottom))
                        shape.fill(Color.white.opacity(hovered && !pressed ? 0.08 : 0))
                        shape.fill(Color.black.opacity(pressed || style.active ? 0.14 : 0))
                        shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0.04)],
                                                          startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    case .raised:
                        shape.fill(pressed || style.active ? Fluid.surface4 : (hovered ? Fluid.surface3 : Fluid.surface2))
                        shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                        shape.strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                            .mask(Rectangle().frame(height: 1.5).frame(maxHeight: .infinity, alignment: .top))
                    default:
                        shape.fill(fill(pressed: pressed))
                        if style.variant == .tertiary {
                            shape.strokeBorder(Fluid.border, lineWidth: 1)
                        }
                    }
                }
                .shadow(color: style.variant == .accent ? Brand.base.opacity(hovered ? 0.45 : 0.3) : .clear, radius: 8, y: 2)
                .padding(pressed ? 1 : 0)
                .animation(.timingCurve(0.23, 1, 0.32, 1, duration: pressed ? 0.08 : 0.18), value: pressed)
            }
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: Fluid.Radius.focusRing, style: .continuous)
                        .strokeBorder(Fluid.focusRing, lineWidth: 1)
                        .padding(-2)
                }
            }
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.5)
            .animation(.easeOut(duration: 0.08), value: hovered)
            .onHover { hovered = $0 && isEnabled }
            .focusEffectDisabled()
    }

    private var labelWeight: Font.Weight {
        switch style.variant {
        case .accent: return .semibold
        case .raised: return .medium
        default: return hovered && style.size.isIconOnly ? .semibold : .regular
        }
    }

    private var textColor: Color {
        switch style.variant {
        case .primary: return Fluid.background
        case .accent: return .white
        case .secondary, .tertiary, .raised: return Fluid.foreground
        case .ghost: return hovered || style.active ? Fluid.foreground : Fluid.mutedForeground
        }
    }

    private func fill(pressed: Bool) -> Color {
        let held = pressed || style.active
        switch style.variant {
        case .primary:
            // The foreground color mixed toward the background: 90% hovered, 80% pressed.
            let mix = held ? 0.8 : (hovered ? 0.9 : 1)
            return Fluid.foreground.mix(with: Fluid.background, by: 1 - mix)
        case .secondary:
            return held ? Fluid.tint : (hovered ? Fluid.tintHover : Fluid.tint)
        case .tertiary, .ghost:
            return held ? Fluid.active : (hovered ? Fluid.hover : .clear)
        case .accent, .raised:
            return .clear
        }
    }
}

/// A Fluid button with a text label and optional icons (SF Symbol names).
struct FluidButton: View {
    let title: String
    var icon: String?
    var trailingIcon: String?
    var variant: FluidButtonVariant = .primary
    var size: FluidButtonSize = .compact
    var active = false
    var loading = false
    let action: () -> Void

    init(_ title: String, icon: String? = nil, trailingIcon: String? = nil, variant: FluidButtonVariant = .primary,
         size: FluidButtonSize = .compact, active: Bool = false, loading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.trailingIcon = trailingIcon
        self.variant = variant
        self.size = size
        self.active = active
        self.loading = loading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                HStack(spacing: size.gap) {
                    if let icon { Image(systemName: icon).font(.system(size: size.iconSize - 2, weight: .medium)) }
                    Text(title)
                    if let trailingIcon { Image(systemName: trailingIcon).font(.system(size: size.iconSize - 4, weight: .semibold)) }
                }
                .opacity(loading ? 0 : 1)
                if loading { FluidSpinner(size: size.height) }
            }
        }
        .buttonStyle(FluidButtonStyle(variant: variant, size: size, active: active, leadingIcon: icon != nil,
                                      trailingIcon: trailingIcon != nil))
        .disabled(loading)
    }
}

/// A Fluid icon-only button.
struct FluidIconButton: View {
    let systemName: String
    var variant: FluidButtonVariant = .ghost
    var size: FluidButtonSize = .iconCompact
    var active = false
    var help: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName).font(.system(size: size.iconSize - 1))
        }
        .buttonStyle(FluidButtonStyle(variant: variant, size: size, active: active))
        .help(help ?? "")
        .accessibilityLabel(help ?? systemName)
    }
}

/// Fluid's loading glyph: a short dash running round a figure eight, its length breathing in and out.
struct FluidSpinner: View {
    var size: CGFloat = 28
    var color: Color?

    var body: some View {
        SwiftUI.TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            // The dash travels the whole path every 2 s and grows from 15% to 40% and back every 4 s.
            let head = (t / 2).truncatingRemainder(dividingBy: 1)
            let breath = 0.5 - 0.5 * cos(t / 4 * 2 * .pi)
            let length = 0.15 + 0.25 * breath
            // Without a color it takes the surrounding text color, like the label it stands in for.
            if let color {
                segment(from: head, length: length).foregroundStyle(color)
            } else {
                segment(from: head, length: length)
            }
        }
        .frame(width: size, height: size)
    }

    private func segment(from start: Double, length: Double) -> some View {
        let end = start + length
        return ZStack {
            FigureEight().trim(from: start, to: min(end, 1))
                .stroke(style: StrokeStyle(lineWidth: 1.125 * size / 24, lineCap: .round))
            if end > 1 {
                FigureEight().trim(from: 0, to: end - 1)
                    .stroke(style: StrokeStyle(lineWidth: 1.125 * size / 24, lineCap: .round))
            }
        }
    }

    private struct FigureEight: Shape {
        func path(in rect: CGRect) -> Path {
            let s = min(rect.width, rect.height) / 24
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
            var path = Path()
            path.move(to: p(12, 12))
            path.addCurve(to: p(19, 12), control1: p(14, 8.5), control2: p(19, 8.5))
            path.addCurve(to: p(12, 12), control1: p(19, 15.5), control2: p(14, 15.5))
            path.addCurve(to: p(5, 12), control1: p(10, 8.5), control2: p(5, 8.5))
            path.addCurve(to: p(12, 12), control1: p(5, 15.5), control2: p(10, 15.5))
            path.closeSubpath()
            return path
        }
    }
}

// MARK: Switch

/// The switch's track and thumb on their own. Hover stretches the thumb into a pill, pressing stretches it further
/// and squashes it, and the thumb can be dragged across.
struct FluidSwitchTrack: View {
    @Binding var isOn: Bool
    var density: Fluid.Density = .compact
    /// Set by a row that wants its whole area to count as hovering the switch.
    var externalHover: Bool? = nil
    @Environment(\.isEnabled) private var isEnabled
    @State private var hoveredSelf = false
    @State private var pressed = false
    @State private var dragX: CGFloat?

    private var trackWidth: CGFloat { density == .regular ? 34 : 28 }
    private var trackHeight: CGFloat { density == .regular ? 20 : 16 }
    private var thumbSize: CGFloat { density == .regular ? 16 : 12 }
    private var pillExtend: CGFloat { 2 }
    private var pressExtend: CGFloat { density == .regular ? 4 : 3 }
    private var pressShrink: CGFloat { density == .regular ? 4 : 3 }
    private let offset: CGFloat = 2
    private var travel: CGFloat { trackWidth - thumbSize - offset * 2 }

    var body: some View {
        let hovered = externalHover ?? hoveredSelf
        let width = pressed ? thumbSize + pressExtend : (hovered ? thumbSize + pillExtend : thumbSize)
        let height = pressed ? thumbSize - pressShrink : thumbSize
        // When on, the extra width grows leftward so the outer edge stays 2 pt from the track's end.
        let restingX = isOn ? offset + travel - (width - thumbSize) : offset
        let x = dragX.map { min(max($0, offset), offset + travel - (width - thumbSize)) } ?? restingX

        Capsule()
            .fill(isOn ? (hovered ? Fluid.switchOnHover : Fluid.switchOn)
                       : (hovered ? Fluid.accent.mix(with: .white, by: 0.1) : Fluid.accent))
            .animation(.easeOut(duration: 0.08), value: hovered)
            .animation(.easeOut(duration: 0.08), value: isOn)
            .frame(width: trackWidth, height: trackHeight)
            .overlay(alignment: .topLeading) {
                Capsule()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
                    .frame(width: width, height: height)
                    .offset(x: x, y: offset + (thumbSize - height) / 2)
                    .animation(dragX == nil ? Fluid.Motion.moderate : nil, value: x)
                    .animation(Fluid.Motion.moderate, value: width)
                    .animation(Fluid.Motion.moderate, value: height)
            }
            .contentShape(Rectangle())
            .onHover { hoveredSelf = $0 && isEnabled }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEnabled else { return }
                        pressed = true
                        // Under 2 pt of travel the press is still a click.
                        if abs(value.translation.width) > 2 {
                            dragX = restingXFor(isOn) + value.translation.width
                        }
                    }
                    .onEnded { value in
                        guard isEnabled else { return }
                        pressed = false
                        if let dragX {
                            // A drag released past the midpoint flips the switch.
                            let past = dragX + thumbSize / 2 > trackWidth / 2
                            self.dragX = nil
                            if past != isOn { isOn = past }
                        } else {
                            isOn.toggle()
                        }
                    }
            )
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(isOn ? "On" : "Off")
            .accessibilityAction { isOn.toggle() }
    }

    private func restingXFor(_ on: Bool) -> CGFloat { on ? offset + travel : offset }
}

/// Fluid's switch: a whole labelled row, where a click anywhere toggles. The label brightens when on.
struct FluidSwitch: View {
    let title: String
    @Binding var isOn: Bool
    var density: Fluid.Density = .compact
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    var body: some View {
        HStack(spacing: density.gap + 4) {
            FluidSwitchTrack(isOn: $isOn, density: density, externalHover: hovered)
            Text(title)
                .font(Fluid.font(.body, density: density))
                .foregroundStyle(isOn ? Fluid.foreground : Fluid.mutedForeground)
                .animation(.easeOut(duration: 0.08), value: isOn)
        }
        .padding(.vertical, density == .compact ? 4 : 8)
        .contentShape(Rectangle())
        .onTapGesture { if isEnabled { isOn.toggle() } }
        .onHover { hovered = $0 && isEnabled }
        .opacity(isEnabled ? 1 : 0.5)
    }
}

// MARK: Slider (scrubber)

/// Fluid's comfortable slider in its scrubber layout: a bordered 32 pt row holding the label and the value, filled
/// up to the value and marked with a 2 pt handle line. A press anywhere jumps there; dragging scrubs. Hovering shows
/// where a click would land, and its value in a small tooltip.
struct FluidSlider: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var step: Double = 0
    var format: (Double) -> String = { String(format: "%.0f%%", $0 * 100) }

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false
    @State private var hoverX: CGFloat?
    @State private var showTooltip = false
    @State private var dragging = false
    @State private var shownFraction: Double?
    @State private var tooltipTask: Task<Void, Never>?

    private let height: CGFloat = 32

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fraction = shownFraction ?? self.fraction(of: value)
            let atMin = fraction <= 0.0001
            let fillWidth = CGFloat(fraction) * width
            let lineX = fillWidth - 9 + (atMin ? 17 : 0)
            let shape = RoundedRectangle(cornerRadius: Fluid.Radius.item, style: .continuous)

            ZStack(alignment: .leading) {
                // Hover preview: a bar from the handle to where a click would land.
                if let hoverX, !dragging {
                    let snapped = snappedFraction(at: hoverX, width: width)
                    let edge = snapped <= 0 ? 0 : (snapped >= 1 ? width : CGFloat(snapped) * width)
                    Rectangle()
                        .fill(Fluid.accent.opacity(0.4))
                        .frame(width: abs(edge - fillWidth))
                        .offset(x: min(edge, fillWidth))
                        .transition(.opacity.animation(.easeOut(duration: 0.15)))
                }
                Rectangle()
                    .fill(Fluid.active)
                    .frame(width: max(0, fillWidth))
                Capsule()
                    .fill(Fluid.foreground.opacity(hovered ? 0.5 : 0.25))
                    .frame(width: 2)
                    .padding(.vertical, hovered ? 7 : 8)
                    .offset(x: lineX)
                HStack(spacing: 12) {
                    Text(title)
                    Spacer(minLength: 0)
                    Text(format(value)).monospacedDigit()
                }
                .font(Fluid.font(.body, density: .regular))
                .foregroundStyle(hovered ? Fluid.foreground : Fluid.mutedForeground)
                .padding(.horizontal, 16)
                .allowsHitTesting(false)
            }
            .frame(width: width, height: height)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Fluid.border, lineWidth: 1))
            .overlay(alignment: .topLeading) {
                if let hoverX, showTooltip, !dragging {
                    FluidValueTip(text: format(valueAt(snappedFraction(at: hoverX, width: width))))
                        .fixedSize()
                        .position(x: CGFloat(snappedFraction(at: hoverX, width: width)) * width, y: -18)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 4)).animation(Fluid.Motion.fast),
                                                removal: .opacity.animation(Fluid.Motion.fastExit)))
                }
            }
            .animation(Fluid.Motion.fast, value: hovered)
            .animation(dragging ? nil : Fluid.Motion.fast, value: fraction)
            .contentShape(Rectangle().inset(by: -8))
            .onContinuousHover { phase in
                guard isEnabled else { return }
                switch phase {
                case .active(let location):
                    if !hovered {
                        hovered = true
                        tooltipTask?.cancel()
                        // The bar shows at once; the tooltip waits 100 ms so sweeping across doesn't flash it.
                        tooltipTask = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(100))
                            if !Task.isCancelled { withAnimation(Fluid.Motion.fast) { showTooltip = true } }
                        }
                    }
                    hoverX = location.x
                case .ended:
                    hovered = false
                    hoverX = nil
                    tooltipTask?.cancel()
                    showTooltip = false
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard isEnabled else { return }
                        let snapped = snappedFraction(at: drag.location.x, width: width)
                        if !dragging {
                            // The press jumps to the value on the fast spring; after that the fill is glued to the pointer.
                            dragging = true
                            withAnimation(Fluid.Motion.fast) { shownFraction = snapped }
                        } else {
                            shownFraction = snapped
                        }
                        value = valueAt(snapped)
                    }
                    .onEnded { _ in
                        dragging = false
                        shownFraction = nil
                    }
            )
        }
        .frame(height: height)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityValue(format(value))
        .accessibilityAdjustableAction { direction in
            let delta = step > 0 ? step : (range.upperBound - range.lowerBound) / 20
            value = min(max(value + (direction == .increment ? delta : -delta), range.lowerBound), range.upperBound)
        }
    }

    private func fraction(of value: Double) -> Double {
        let span = range.upperBound - range.lowerBound
        return span <= 0 ? 0 : min(max((value - range.lowerBound) / span, 0), 1)
    }

    private func valueAt(_ fraction: Double) -> Double {
        range.lowerBound + fraction * (range.upperBound - range.lowerBound)
    }

    private func snappedFraction(at x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        let raw = Double(min(max(x / width, 0), 1))
        guard step > 0 else { return raw }
        let span = range.upperBound - range.lowerBound
        let steps = (raw * span / step).rounded()
        return min(max(steps * step / span, 0), 1)
    }
}

/// The small value bubble Fluid's sliders show above the pointer.
struct FluidValueTip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Fluid.font(.caption, density: .regular, monospacedDigits: true))
            .foregroundStyle(Fluid.background)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Fluid.foreground, in: RoundedRectangle(cornerRadius: Fluid.Radius.item, style: .continuous))
            .allowsHitTesting(false)
    }
}

// MARK: Slider (compact)

/// Fluid's compact slider: a white knob on a hairline pill track, filled up to the knob, with the same hover preview
/// and value tooltip. Used where the value is a position, such as a video's playhead.
struct FluidTrackSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var format: (Double) -> String = { String(format: "%.2f", $0) }
    var onEditingChanged: (Bool) -> Void = { _ in }

    @Environment(\.isEnabled) private var isEnabled
    @State private var hoverX: CGFloat?
    @State private var showTooltip = false
    @State private var dragging = false
    @State private var tooltipTask: Task<Void, Never>?

    private let thumbBox: CGFloat = 20
    private let knob: CGFloat = 16
    private let trackHeight: CGFloat = 18

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let usable = max(1, width - thumbBox)
            let thumbX = CGFloat(fraction(of: value)) * usable
            let inset = (thumbBox - trackHeight) / 2
            let pill = Capsule()

            ZStack(alignment: .topLeading) {
                ZStack(alignment: .leading) {
                    Rectangle().fill(Fluid.accent.opacity(0.4))
                        .frame(width: max(0, thumbX + thumbBox / 2 - inset))
                    if let hoverX, !dragging {
                        let target = min(max(hoverX - thumbBox / 2, 0), usable)
                        let from = thumbX + thumbBox / 2 - inset
                        let to = target + thumbBox / 2 - inset
                        Rectangle().fill(Fluid.accent.opacity(0.4))
                            .frame(width: abs(to - from))
                            .offset(x: min(from, to))
                            .transition(.opacity.animation(.easeOut(duration: 0.15)))
                    }
                }
                .frame(width: width - inset * 2, height: trackHeight, alignment: .leading)
                .clipShape(pill)
                .overlay(pill.strokeBorder(Fluid.border, lineWidth: 1))
                .offset(x: inset, y: 8 + inset)

                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
                    .frame(width: knob, height: knob)
                    .frame(width: thumbBox, height: thumbBox)
                    .offset(x: thumbX, y: 8)
                    .animation(dragging ? nil : Fluid.Motion.fast, value: thumbX)

                if let hoverX, showTooltip, !dragging {
                    let target = min(max(hoverX - thumbBox / 2, 0), usable)
                    FluidValueTip(text: format(range.lowerBound + Double(target / usable) * (range.upperBound - range.lowerBound)))
                        .fixedSize()
                        .position(x: target + thumbBox / 2, y: -6)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 4)).animation(Fluid.Motion.fast),
                                                removal: .opacity.animation(Fluid.Motion.fastExit)))
                }
            }
            .frame(width: width, height: thumbBox + 16, alignment: .topLeading)
            .contentShape(Rectangle().inset(by: -8))
            .onContinuousHover { phase in
                guard isEnabled else { return }
                switch phase {
                case .active(let location):
                    if hoverX == nil {
                        tooltipTask?.cancel()
                        tooltipTask = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(100))
                            if !Task.isCancelled { withAnimation(Fluid.Motion.fast) { showTooltip = true } }
                        }
                    }
                    hoverX = location.x
                case .ended:
                    hoverX = nil
                    tooltipTask?.cancel()
                    showTooltip = false
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard isEnabled else { return }
                        if !dragging { dragging = true; onEditingChanged(true) }
                        let f = Double(min(max((drag.location.x - thumbBox / 2) / usable, 0), 1))
                        value = range.lowerBound + f * (range.upperBound - range.lowerBound)
                    }
                    .onEnded { _ in
                        dragging = false
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: thumbBox + 16)
        .opacity(isEnabled ? 1 : 0.5)
    }

    private func fraction(of value: Double) -> Double {
        let span = range.upperBound - range.lowerBound
        return span <= 0 ? 0 : min(max((value - range.lowerBound) / span, 0), 1)
    }
}
