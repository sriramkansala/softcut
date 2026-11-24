import SwiftUI

// Option cards: a list of choices drawn as cards, each with an icon tile, a title and a line of explanation. They
// are built from Fluid Functionalism's Card (icon media tile, title that turns semibold when selected, hover fill) and
// its selection choreography (one marker that springs from the old choice to the new one), with Softcut's brand purple
// for the marker.

struct FluidChoice<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var subtitle: String?
    var icon: String
    /// A small glyph on a purple badge over the icon's corner.
    var badge: String?
    var id: Value { value }

    init(_ value: Value, _ title: String, subtitle: String? = nil, icon: String, badge: String? = nil) {
        self.value = value
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.badge = badge
    }
}

/// A dark rounded tile holding an icon, with an optional purple badge over its lower right corner.
struct FluidIconTile: View {
    let icon: String
    var badge: String?
    var size: CGFloat = 40
    var isLit = false
    /// A color for the icon itself, such as a timeline lane's.
    var tint: Color?

    var body: some View {
        let radius = size * 0.26
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: [Color(fluidHex: 0x2E2E2E), Color(fluidHex: 0x1C1C1C)], startPoint: .top, endPoint: .bottom))
            shape.strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
            shape.strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                .mask(Rectangle().frame(height: 1.5).frame(maxHeight: .infinity, alignment: .top))
            Image(systemName: icon)
                .font(.system(size: size * 0.4, weight: isLit ? .medium : .regular))
                .foregroundStyle(tint ?? (isLit ? Fluid.foreground : Fluid.mutedForeground))
                .offset(x: badge == nil ? 0 : -size * 0.06, y: badge == nil ? 0 : -size * 0.06)
            if let badge {
                Circle()
                    .fill(LinearGradient(colors: [Brand.light, Brand.deep], startPoint: .top, endPoint: .bottom))
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1.5).padding(-1.5))
                    .overlay(Image(systemName: badge).font(.system(size: size * 0.2, weight: .bold)).foregroundStyle(.white))
                    .frame(width: size * 0.4, height: size * 0.4)
                    .offset(x: size * 0.2, y: size * 0.2)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.08), value: isLit)
    }
}

/// Choices as a column of cards. The chosen card wears a purple ring that springs to a newly chosen card, and its
/// title turns semibold.
struct FluidOptionCards<Value: Hashable>: View {
    @Binding var selection: Value
    let choices: [FluidChoice<Value>]
    var density: Fluid.Density = .compact

    @Environment(\.isEnabled) private var isEnabled
    @State private var space = "fluid-options-\(UUID().uuidString)"
    @State private var frames: [Value: CGRect] = [:]
    @State private var hovered: Value?
    @State private var settled = false

    private var tile: CGFloat { density == .compact ? 38 : 46 }
    private let radius: CGFloat = 12

    var body: some View {
        VStack(spacing: 8) {
            ForEach(choices) { choice in card(choice) }
        }
        .overlay(alignment: .topLeading) { ring }
        .coordinateSpace(name: space)
        .opacity(isEnabled ? 1 : 0.5)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { settled = true } }
        .accessibilityRepresentation {
            Picker("", selection: $selection) {
                ForEach(choices) { Text($0.title).tag($0.value) }
            }
            .pickerStyle(.radioGroup)
        }
    }

    private func card(_ choice: FluidChoice<Value>) -> some View {
        let selected = choice.value == selection
        let lit = selected || hovered == choice.value
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return HStack(spacing: 12) {
            FluidIconTile(icon: choice.icon, badge: choice.badge, size: tile, isLit: lit)
            VStack(alignment: .leading, spacing: 2) {
                ZStack(alignment: .leading) {
                    Text(choice.title).font(Fluid.font(.subtitle, .semibold, density: density)).hidden()
                    Text(choice.title).font(Fluid.font(.subtitle, selected ? .semibold : .normal, density: density))
                }
                .foregroundStyle(Fluid.foreground)
                .lineLimit(1)
                if let subtitle = choice.subtitle {
                    Text(subtitle)
                        .font(Fluid.font(.body, density: density))
                        .foregroundStyle(Fluid.mutedForeground)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(density == .compact ? 9 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(Color.white.opacity(selected ? 0.05 : (hovered == choice.value ? 0.055 : 0.03))))
        .contentShape(shape)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(space)) } action: { frames[choice.value] = $0 }
        .onHover { inside in
            guard isEnabled else { return }
            if inside { hovered = choice.value } else if hovered == choice.value { hovered = nil }
        }
        .onTapGesture { if isEnabled { selection = choice.value } }
        .animation(.easeOut(duration: 0.08), value: hovered)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(choice.title + (choice.subtitle.map { ", \($0)" } ?? ""))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var ring: some View {
        if let rect = frames[selection] {
            ZStack {
                RoundedRectangle(cornerRadius: radius + 1, style: .continuous)
                    .strokeBorder(Brand.base, lineWidth: 1.5)
                    .shadow(color: Brand.base.opacity(0.55), radius: 6)
                RoundedRectangle(cornerRadius: radius - 0.5, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    .padding(1.5)
            }
            .frame(width: rect.width + 2, height: rect.height + 2)
            .offset(x: rect.minX - 1, y: rect.minY - 1)
            .animation(settled ? Fluid.Motion.moderate : nil, value: rect)
            .allowsHitTesting(false)
        }
    }
}
