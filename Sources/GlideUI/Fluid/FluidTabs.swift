import SwiftUI

// Fluid Functionalism's Tabs (a segmented control on a muted track) and TabsSubtle (standalone pills, optionally
// icons only with the selected tab's label sliding open). Ported from the MIT-licensed originals by Micka Touillaud.

struct FluidTabItem<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var icon: String?
    var id: Value { value }

    init(_ value: Value, _ title: String, icon: String? = nil) {
        self.value = value
        self.title = title
        self.icon = icon
    }
}

enum FluidTabsStyle {
    /// The segmented control: a muted track with the selected tab raised on it.
    case segmented
    /// No track: the selected tab is a translucent pill sitting on the surface.
    case subtle
    /// Subtle, icons only, with the selected tab's label sliding open next to its icon.
    case subtleIcons
}

/// One raised pill marks the selected tab and travels to a new one on the moderate spring. A faint hover pill
/// previews the next click: it is born at the selected pill and slides out to the tab under the pointer, and when the
/// pointer leaves it slides back in. Only the selected label turns semibold, and every tab reserves its bold width,
/// so nothing shifts.
struct FluidTabs<Value: Hashable>: View {
    @Binding var selection: Value
    let items: [FluidTabItem<Value>]
    var style: FluidTabsStyle = .segmented
    var density: Fluid.Density = .compact
    /// Stretch the tabs to share the available width equally.
    var fill = false

    @Environment(\.fluidSurfaceLevel) private var substrate
    @Environment(\.isEnabled) private var isEnabled
    @State private var space = "fluid-tabs-\(UUID().uuidString)"
    @State private var frames: [Value: CGRect] = [:]
    @State private var hoveredTab: Value?
    @State private var hoverRect: CGRect?
    @State private var hoverOpacity = 0.0
    @State private var labelWidths: [Value: CGFloat] = [:]
    /// The pill lands without animating on first render, and only travels once the strip has settled.
    @State private var settled = false

    private var segmented: Bool { style == .segmented }
    private var itemHeight: CGFloat { segmented ? density.segmentItem : density.control }
    private var itemPadding: CGFloat { segmented ? 12 : density.paddingX }

    var body: some View {
        FluidFillRow(fills: fill) {
            ForEach(items) { item in
                tab(item)
            }
        }
        .padding(segmented ? density.segmentPad : 0)
        .background(alignment: .topLeading) { pills }
        .background {
            if segmented {
                RoundedRectangle(cornerRadius: Fluid.Radius.container, style: .continuous).fill(Fluid.muted)
            }
        }
        .coordinateSpace(name: space)
        .contentShape(Rectangle())
        .onContinuousHover(coordinateSpace: .named(space)) { phase in
            guard isEnabled else { return }
            switch phase {
            case .active(let location): hover(at: location)
            case .ended: endHover()
            }
        }
        .opacity(isEnabled ? 1 : 0.5)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { settled = true } }
        .accessibilityRepresentation {
            Picker("", selection: $selection) {
                ForEach(items) { Text($0.title).tag($0.value) }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: Tabs

    @ViewBuilder
    private func tab(_ item: FluidTabItem<Value>) -> some View {
        let selected = item.value == selection
        let lit = selected || item.value == hoveredTab
        let collapses = style == .subtleIcons && item.icon != nil
        HStack(spacing: collapses ? 0 : density.gap) {
            if let icon = item.icon {
                Image(systemName: icon)
                    .font(.system(size: density.icon - 1, weight: lit ? .semibold : .regular))
                    .frame(width: density.icon, height: density.icon)
            }
            if collapses {
                label(item.title, selected: selected)
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { labelWidths[item.value] = $0 }
                    .frame(width: selected ? labelWidths[item.value] : 0, alignment: .leading)
                    .clipped()
                    .opacity(selected ? 1 : 0)
                    .padding(.leading, selected ? (density == .compact ? 6 : 8) : 0)
                    .animation(Fluid.Motion.fast, value: selected)
            } else {
                label(item.title, selected: selected)
            }
        }
        .foregroundStyle(lit ? Fluid.foreground : Fluid.mutedForeground)
        .animation(.easeOut(duration: 0.08), value: lit)
        .padding(.horizontal, itemPadding)
        .frame(maxWidth: fill ? .infinity : nil)
        .frame(height: itemHeight)
        .contentShape(Rectangle())
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(space)) } action: { frames[item.value] = $0 }
        .onTapGesture { if isEnabled { select(item.value) } }
        .help(collapses && !selected ? item.title : "")
    }

    private func label(_ title: String, selected: Bool) -> some View {
        ZStack {
            // The bold copy reserves the width the label has when selected.
            Text(title).font(Fluid.font(.body, .semibold, density: density)).hidden()
            Text(title).font(Fluid.font(.body, selected ? .semibold : .normal, density: density))
        }
        .lineLimit(1)
    }

    // MARK: Pills

    @ViewBuilder
    private var pills: some View {
        ZStack(alignment: .topLeading) {
            if let rect = frames[selection] {
                let dimmed = hoveredTab != nil && hoveredTab != selection
                Group {
                    if segmented {
                        Color.clear.fluidSurface(min(substrate + 3, 8), radius: Fluid.Radius.item)
                    } else {
                        RoundedRectangle(cornerRadius: Fluid.Radius.item, style: .continuous).fill(Fluid.active)
                    }
                }
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .opacity(dimmed ? (segmented ? 0.85 : 0.8) : 1)
                .animation(settled ? Fluid.Motion.moderate : nil, value: rect)
                .animation(.linear(duration: 0.08), value: dimmed)
            }
            if let hoverRect {
                RoundedRectangle(cornerRadius: Fluid.Radius.item, style: .continuous)
                    .fill(segmented ? Fluid.hover : Fluid.active)
                    .frame(width: hoverRect.width, height: hoverRect.height)
                    .offset(x: hoverRect.minX, y: hoverRect.minY)
                    .opacity(hoverOpacity)
            }
        }
        .allowsHitTesting(false)
    }

        // MARK: Hover choreography
}

/// A row of tabs. Each tab keeps the width its label needs; when the row fills a wider space, the spare room is
/// shared out equally on top, so long labels never get cut short to make the tabs equal.
private struct FluidFillRow: Layout {
    var fills: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let natural = sizes.reduce(0) { $0 + $1.width }
        let width = fills ? max(natural, proposal.width ?? natural) : natural
        return CGSize(width: width, height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let natural = sizes.reduce(0) { $0 + $1.width }
        let extra = fills && !subviews.isEmpty ? max(0, bounds.width - natural) / CGFloat(subviews.count) : 0
        var x = bounds.minX
        for (subview, size) in zip(subviews, sizes) {
            let width = size.width + extra
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(width: width, height: size.height))
            x += width
        }
    }
}

private extension FluidTabs {
    // MARK: Hover choreography (continued)

    private func nearestTab(to point: CGPoint) -> Value? {
        if let inside = items.first(where: { frames[$0.value].map { $0.minX <= point.x && point.x <= $0.maxX } ?? false }) {
            return inside.value
        }
        return items.min { a, b in
            abs((frames[a.value]?.midX ?? .infinity) - point.x) < abs((frames[b.value]?.midX ?? .infinity) - point.x)
        }?.value
    }

    private func hover(at point: CGPoint) {
        guard let tab = nearestTab(to: point), tab != hoveredTab else { return }
        hoveredTab = tab
        guard let target = frames[tab] else { return }
        if tab == selection {
            // Over the selected tab the raised pill says it all: the preview fades where it is.
            withAnimation(Fluid.Motion.fastExit) { hoverOpacity = 0 }
            return
        }
        if hoverRect == nil || hoverOpacity == 0 {
            // A fresh preview starts inside the selected pill, so it reads as leaving the current choice.
            var still = Transaction(animation: nil)
            still.disablesAnimations = true
            withTransaction(still) {
                hoverRect = frames[selection] ?? target
                hoverOpacity = 0
            }
            DispatchQueue.main.async {
                withAnimation(Fluid.Motion.fast) { hoverRect = target }
                withAnimation(.linear(duration: 0.08)) { hoverOpacity = 0.4 }
            }
        } else {
            withAnimation(Fluid.Motion.fast) { hoverRect = target }
            withAnimation(.linear(duration: 0.08)) { hoverOpacity = 0.4 }
        }
    }

    private func endHover() {
        hoveredTab = nil
        guard hoverOpacity > 0 else { return }
        // Leaving the strip: the preview slides back into the selected pill as it fades.
        withAnimation(Fluid.Motion.moderate) { hoverRect = frames[selection] ?? hoverRect }
        withAnimation(.linear(duration: 0.06)) { hoverOpacity = 0 }
    }

    private func select(_ value: Value) {
        selection = value
        withAnimation(Fluid.Motion.fastExit) { hoverOpacity = 0 }
    }
}
