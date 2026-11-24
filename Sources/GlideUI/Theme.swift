import SwiftUI

/// The editor's look, built on Fluid Functionalism's dark surfaces (see Fluid/Fluid.swift).
enum Theme {
    /// The window behind everything: surface 1.
    static let canvas = Fluid.surface1
    /// Bars and the sidebar: surface 2.
    static let panel = Fluid.surface2
    /// Things lifted off a panel: surface 3.
    static let raised = Fluid.surface3
    /// Wells and empty tracks.
    static let track = Fluid.muted
    static let hairline = Fluid.border
    static let gap: CGFloat = 16

    /// The one chromatic accent, Fluid's focus blue.
    static let accent = Fluid.focusRing
    static let clip = Color(red: 0.30, green: 0.46, blue: 0.86)
    static let zoom = Color(red: 0.93, green: 0.58, blue: 0.22)
    static let playhead = Color(red: 1.0, green: 0.36, blue: 0.36)
}

/// Glide's brand purple: the Export button, the selected pane in the rail and the ring on a chosen option.
enum Brand {
    static let base = Color(fluidHex: 0x7C5CFF)
    static let light = Color(fluidHex: 0x8F5BFF)
    static let deep = Color(fluidHex: 0x6A35F0)
    /// Icons on a brand-tinted tile.
    static let lavender = Color(fluidHex: 0xCBBDFF)
}

/// A group of controls in the settings panel, flat under a hairline. A group that can be switched off has its switch in
/// the header, and shows its controls only while on.
struct InspectorSection<Content: View>: View {
    let title: String
    var isOn: Binding<Bool>?
    @ViewBuilder var content: Content

    init(title: String, isOn: Binding<Bool>? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.isOn = isOn
        self.content = content()
    }

    var body: some View {
        let open = isOn?.wrappedValue ?? true
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(Fluid.font(.body, .semibold))
                    .foregroundStyle(open ? Fluid.foreground : Fluid.mutedForeground)
                Spacer()
                if let isOn { FluidSwitchTrack(isOn: isOn) }
            }
            .frame(height: 36)
            .contentShape(Rectangle())
            .onTapGesture {
                if let isOn { withAnimation(open ? .easeInOut(duration: 0.12) : Fluid.Motion.moderate) { isOn.wrappedValue.toggle() } }
            }
            .accessibilityElement(children: .contain)

            VStack(alignment: .leading, spacing: 8) { content }
                .padding(.bottom, 12)
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: open ? nil : 0, alignment: .top)
                // Only what is folded away is cut off, with room left for an outline around what comes first.
                .mask { Rectangle().padding(-6) }
                .opacity(open ? 1 : 0)
                .allowsHitTesting(open)
                .accessibilityHidden(!open)
        }
        .padding(.horizontal, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(Fluid.border).frame(height: 1) }
        .animation(open ? Fluid.Motion.moderate : .easeInOut(duration: 0.12), value: open)
    }
}

/// A Fluid scrubber slider: the name and current value sit inside the bar.
struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var display: (Double) -> String = { String(format: "%.0f%%", $0 * 100) }
    var isEnabled = true

    var body: some View {
        FluidSlider(title: title, value: $value, range: range, format: display)
            .disabled(!isEnabled)
    }
}

/// A name on the left and a Fluid switch on the right, the same way round as a section's header.
struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    var help: String?

    var body: some View {
        HStack {
            Text(title).font(Fluid.font(.body)).foregroundStyle(isOn ? Fluid.foreground : Fluid.mutedForeground)
            Spacer()
            FluidSwitchTrack(isOn: $isOn)
        }
        .frame(minHeight: 28)
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
        .fluidTooltip(help)
    }
}

/// A label on the left and a control on the right, the row of Fluid's settings panels.
struct SettingRow<Control: View>: View {
    let title: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(Fluid.font(.body)).foregroundStyle(Fluid.mutedForeground)
            Spacer(minLength: 8)
            control
        }
        .frame(minHeight: 28)
    }
}

/// A line of muted help text.
struct HelpText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Fluid.font(.caption))
            .foregroundStyle(Fluid.mutedForeground)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A thin, non-interactive progress bar drawn like Fluid's compact slider track.
struct FluidProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().strokeBorder(Fluid.border, lineWidth: 1)
                Capsule().fill(Fluid.foreground.opacity(0.4))
                    .frame(width: max(6, proxy.size.width * min(max(fraction, 0), 1)))
                    .animation(Fluid.Motion.moderate, value: fraction)
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityValue("\(Int(fraction * 100)) percent")
    }
}

extension View {
    /// A rounded raised surface, used for groups inside the sidebar.
    func raisedSurface(padding: CGFloat = 8) -> some View {
        self.padding(padding)
            .background(Fluid.hover, in: RoundedRectangle(cornerRadius: Fluid.Radius.container, style: .continuous))
    }
}

func timecode(_ seconds: Double, tenths: Bool = true) -> String {
    let clamped = max(0, seconds) + 1e-6
    let minutes = Int(clamped) / 60
    let rest = clamped - Double(minutes * 60)
    return tenths ? String(format: "%d:%04.1f", minutes, rest) : String(format: "%d:%02d", minutes, Int(rest))
}
