import AppKit
import SwiftUI

// Fluid Functionalism's Sidebar and SidebarMenu. Ported from the MIT-licensed originals by Micka Touillaud.

struct FluidSidebarItem<ID: Hashable>: Identifiable {
    let id: ID
    var title: String
    var icon: String?
    var badge: String?
}

struct FluidSidebarSection<ID: Hashable>: Identifiable {
    var title: String?
    var items: [FluidSidebarItem<ID>]
    var id: String { title ?? items.map { "\($0.id)" }.joined() }
}

/// A sidebar column beside the main content. It sits on the page with a hairline on its inner edge; dragging that
/// edge resizes it (160–360 pt), dragging it below 104 pt or clicking it collapses it, and it slides open and shut.
struct FluidSidebarLayout<Sidebar: View, Content: View>: View {
    @Binding var isOpen: Bool
    @Binding var width: CGFloat
    @ViewBuilder var sidebar: Sidebar
    @ViewBuilder var content: Content

    @State private var dragStart: CGFloat?
    @State private var railHovered = false

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                sidebar
                    .frame(width: width)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .offset(x: isOpen ? 0 : -width)
            }
            .frame(width: isOpen ? width : 0, alignment: .leading)
            .clipped()
            .overlay(alignment: .trailing) { if isOpen { rail } }
            .transaction { if dragStart != nil { $0.animation = nil } }
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var rail: some View {
        ZStack {
            Rectangle().fill(Fluid.border).frame(width: 1)
            Rectangle().fill(Fluid.foreground.opacity(railHovered || dragStart != nil ? 0.25 : 0)).frame(width: 1)
        }
        .frame(width: 8)
        .contentShape(Rectangle())
        .offset(x: 4)
        .onHover { inside in
            railHovered = inside
            if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        }
        .animation(.easeOut(duration: 0.08), value: railHovered)
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { drag in
                if dragStart == nil { dragStart = width }
                guard abs(drag.translation.width) >= 4 else { return }
                width = min(max((dragStart ?? width) + drag.translation.width, 160), 360)
            }
            .onEnded { drag in
                let start = dragStart ?? width
                dragStart = nil
                if abs(drag.translation.width) < 4 || start + drag.translation.width < 104 {
                    // A click, or a drag well past the minimum, collapses it.
                    if start + drag.translation.width < 104 { width = 160 }
                    withAnimation(Fluid.Motion.slowExit) { isOpen = false }
                }
            })
        .fluidTooltip("Drag to resize · Click to collapse")
    }
}

/// The sidebar's menu: rows with an icon, a label and an optional count. One hover background glides between rows,
/// the current row sits on an `active` background that springs to a newly chosen row, and its label turns semibold.
struct FluidSidebarMenu<ID: Hashable>: View {
    let sections: [FluidSidebarSection<ID>]
    @Binding var selection: ID
    var density: Fluid.Density = .regular

    @State private var space = "fluid-sidebar-\(UUID().uuidString)"
    @State private var frames: [ID: CGRect] = [:]
    @State private var lit: ID?
    @State private var litRect: CGRect?
    @State private var litOpacity = 0.0

    private var rowHeight: CGFloat { density == .compact ? 28 : 32 }
    private var allItems: [FluidSidebarItem<ID>] { sections.flatMap(\.items) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 0) {
                    if let title = section.title {
                        Text(title)
                            .font(Fluid.font(.caption, density: density))
                            .foregroundStyle(Fluid.mutedForeground)
                            .padding(.horizontal, 8)
                            .frame(height: 32)
                    }
                    ForEach(section.items) { item in row(item) }
                }
                .padding(8)
            }
        }
        .background(alignment: .topLeading) { overlays }
        .coordinateSpace(name: space)
        .contentShape(Rectangle())
        .onContinuousHover(coordinateSpace: .named(space)) { phase in
            switch phase {
            case .active(let point):
                let id = allItems.first { frames[$0.id].map { $0.minY <= point.y && point.y <= $0.maxY } ?? false }?.id
                    ?? allItems.min { abs((frames[$0.id]?.midY ?? .infinity) - point.y) < abs((frames[$1.id]?.midY ?? .infinity) - point.y) }?.id
                guard let id, id != lit, let rect = frames[id] else { return }
                let fresh = lit == nil || litOpacity == 0
                lit = id
                if fresh {
                    var still = Transaction(animation: nil)
                    still.disablesAnimations = true
                    withTransaction(still) { litRect = rect }
                    withAnimation(.linear(duration: 0.08)) { litOpacity = 1 }
                } else {
                    withAnimation(Fluid.Motion.fast) { litRect = rect }
                }
            case .ended:
                lit = nil
                withAnimation(Fluid.Motion.fastExit) { litOpacity = 0 }
            }
        }
        .onTapGesture { if let lit { selection = lit } }
    }

    private func row(_ item: FluidSidebarItem<ID>) -> some View {
        let active = item.id == selection
        let on = active || lit == item.id
        return HStack(spacing: 8) {
            if let icon = item.icon {
                Image(systemName: icon)
                    .font(.system(size: density.icon - 2, weight: on ? .semibold : .regular))
                    .frame(width: density.icon, height: density.icon)
            }
            ZStack(alignment: .leading) {
                Text(item.title).font(Fluid.font(.body, .semibold, density: density)).hidden()
                Text(item.title).font(Fluid.font(.body, active ? .semibold : .normal, density: density))
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let badge = item.badge {
                Text(badge)
                    .font(Fluid.font(.micro, active ? .semibold : .normal, density: .regular, monospacedDigits: true))
                    .foregroundStyle(active ? Fluid.foreground : Fluid.mutedForeground)
                    .frame(minWidth: 20)
            }
        }
        .foregroundStyle(on ? Fluid.foreground : Fluid.mutedForeground)
        .animation(.easeOut(duration: 0.08), value: on)
        .padding(.leading, 8)
        .padding(.trailing, item.badge == nil ? 8 : 6)
        .frame(height: rowHeight)
        .contentShape(Rectangle())
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(space)) } action: { frames[item.id] = $0 }
        .onTapGesture { selection = item.id }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title + (item.badge.map { ", \($0)" } ?? ""))
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var overlays: some View {
        let shape = RoundedRectangle(cornerRadius: Fluid.Radius.item, style: .continuous)
        ZStack(alignment: .topLeading) {
            if let rect = frames[selection] {
                shape.fill(Fluid.active)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .animation(Fluid.Motion.moderate, value: rect)
            }
            if let litRect {
                shape.fill(Fluid.hover)
                    .frame(width: litRect.width, height: litRect.height)
                    .offset(x: litRect.minX, y: litRect.minY)
                    .opacity(litOpacity)
            }
        }
        .allowsHitTesting(false)
    }
}

/// The ghost icon button that opens and closes a sidebar.
struct FluidSidebarTrigger: View {
    @Binding var isOpen: Bool

    var body: some View {
        FluidIconButton(systemName: "sidebar.left", help: isOpen ? "Collapse sidebar" : "Expand sidebar") {
            withAnimation(isOpen ? Fluid.Motion.slowExit : Fluid.Motion.slow) { isOpen.toggle() }
        }
    }
}
