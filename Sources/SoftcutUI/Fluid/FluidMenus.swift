import SwiftUI

// Fluid Functionalism's Select, Dropdown and MenuItem, sharing one popup list. Ported from the MIT-licensed
// originals by Micka Touillaud.

/// The check that marks a chosen row: it draws in over 80 ms and undraws in 40 ms.
struct FluidCheckmark: View {
    var isOn: Bool
    var size: CGFloat = 14

    var body: some View {
        CheckPath()
            .trim(from: 0, to: isOn ? 1 : 0)
            .stroke(style: StrokeStyle(lineWidth: 2 * size / 24 * 1.15, lineCap: .round, lineJoin: .round))
            .foregroundStyle(Fluid.foreground)
            .frame(width: size, height: size)
            .animation(isOn ? .easeOut(duration: 0.08) : .easeIn(duration: 0.04), value: isOn)
    }

    private struct CheckPath: Shape {
        func path(in rect: CGRect) -> Path {
            let s = min(rect.width, rect.height) / 24
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + 4 * s, y: rect.minY + 12 * s))
            path.addLine(to: CGPoint(x: rect.minX + 9 * s, y: rect.minY + 17 * s))
            path.addLine(to: CGPoint(x: rect.minX + 20 * s, y: rect.minY + 6 * s))
            return path
        }
    }
}

/// One row of a Fluid menu.
struct FluidMenuRow: Identifiable {
    enum Kind { case item, separator, label }

    let id: AnyHashable
    var kind = Kind.item
    var title = ""
    var icon: String?
    /// `nil` for a plain action; true or false for a choice.
    var checked: Bool?
    var isDisabled = false
    var isDestructive = false
    var action: () -> Void = {}

    static func item(_ title: String, icon: String? = nil, checked: Bool? = nil, disabled: Bool = false,
                     destructive: Bool = false, id: AnyHashable? = nil, action: @escaping () -> Void) -> FluidMenuRow {
        FluidMenuRow(id: id ?? AnyHashable(title), title: title, icon: icon, checked: checked, isDisabled: disabled,
                     isDestructive: destructive, action: action)
    }

    static func separator(_ id: AnyHashable = UUID()) -> FluidMenuRow { FluidMenuRow(id: id, kind: .separator) }
    static func label(_ title: String) -> FluidMenuRow { FluidMenuRow(id: AnyHashable("label-" + title), kind: .label, title: title) }
}

/// The rows of a popup list. The row nearest the pointer is lit by one highlight that slides between rows; the
/// checked row sits on a `bg-active` marker that springs to a newly picked row.
struct FluidMenuList: View {
    let rows: [FluidMenuRow]
    var density: Fluid.Density = .compact
    /// Dropdown makes the checked row semibold; Select doesn't.
    var boldChecked = false
    /// Select keeps a slot for the check so the popup's width never changes.
    var reserveCheckSlot = true
    /// Dropdown lights its first row when it opens.
    var lightFirstRow = false
    var minWidth: CGFloat = 0

    @State private var space = "fluid-menu-\(UUID().uuidString)"
    @State private var frames: [AnyHashable: CGRect] = [:]
    @State private var lit: AnyHashable?
    @State private var litRect: CGRect?
    @State private var litOpacity = 0.0
    @State private var markerShown = false

    private var checkedRow: FluidMenuRow? { rows.first { $0.checked == true } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                switch row.kind {
                case .separator:
                    Rectangle().fill(Fluid.divider).frame(height: 1).padding(.vertical, 4).padding(.horizontal, -4)
                case .label:
                    Text(row.title)
                        .font(Fluid.font(.caption, density: density))
                        .foregroundStyle(Fluid.mutedForeground)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                case .item:
                    item(row)
                }
            }
        }
        .frame(minWidth: minWidth, alignment: .leading)
        .background(alignment: .topLeading) { overlays }
        .coordinateSpace(name: space)
        .contentShape(Rectangle())
        .onContinuousHover(coordinateSpace: .named(space)) { phase in
            switch phase {
            case .active(let point): light(nearest(to: point))
            case .ended: light(nil)
            }
        }
        .onTapGesture {
            // A click in the padding or a gap goes to the lit row.
            if let lit, let row = rows.first(where: { $0.id == lit }), !row.isDisabled { row.action() }
        }
        .onAppear {
            if lightFirstRow, let first = rows.first(where: { $0.kind == .item && !$0.isDisabled }) {
                DispatchQueue.main.async { light(first.id) }
            }
        }
    }

    private func item(_ row: FluidMenuRow) -> some View {
        let highlighted = lit == row.id
        let on = highlighted || row.checked == true
        let color: Color = row.isDestructive ? Fluid.destructive : (on ? Fluid.foreground : Fluid.mutedForeground)
        return HStack(spacing: density.gap + (density == .compact ? 2 : 0)) {
            if let icon = row.icon {
                Image(systemName: icon)
                    .font(.system(size: density.icon - 2, weight: on ? .semibold : .regular))
                    .frame(width: density.icon, height: density.icon)
            }
            ZStack(alignment: .leading) {
                Text(row.title).font(Fluid.font(.body, .semibold, density: density)).hidden()
                Text(row.title).font(Fluid.font(.body, boldChecked && row.checked == true ? .semibold : .normal, density: density))
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            if reserveCheckSlot || row.checked == true {
                FluidCheckmark(isOn: row.checked == true, size: density.icon)
            }
        }
        .foregroundStyle(color)
        .animation(.easeOut(duration: 0.08), value: on)
        .padding(.horizontal, density.itemPaddingX + 2)
        .frame(height: density.control)
        .contentShape(Rectangle())
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(space)) } action: { frames[row.id] = $0 }
        .onTapGesture { if !row.isDisabled { row.action() } }
        .opacity(row.isDisabled ? 0.5 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.title)
        .accessibilityAddTraits(row.checked == true ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { if !row.isDisabled { row.action() } }
    }

    @ViewBuilder
    private var overlays: some View {
        let shape = RoundedRectangle(cornerRadius: Fluid.Radius.item, style: .continuous)
        ZStack(alignment: .topLeading) {
            if let checked = checkedRow, let rect = frames[checked.id] {
                shape.fill(Fluid.active)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .animation(markerShown ? Fluid.Motion.moderate : nil, value: rect)
                    .onAppear { DispatchQueue.main.async { markerShown = true } }
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

    private func nearest(to point: CGPoint) -> AnyHashable? {
        let candidates = rows.filter { $0.kind == .item && !$0.isDisabled }
        if let inside = candidates.first(where: { frames[$0.id].map { $0.minY <= point.y && point.y <= $0.maxY } ?? false }) {
            return inside.id
        }
        return candidates.min { abs((frames[$0.id]?.midY ?? .infinity) - point.y) < abs((frames[$1.id]?.midY ?? .infinity) - point.y) }?.id
    }

    private func light(_ id: AnyHashable?) {
        guard id != lit else { return }
        let wasLit = lit != nil && litOpacity > 0
        lit = id
        guard let id, let rect = frames[id] else {
            withAnimation(Fluid.Motion.fastExit) { litOpacity = 0 }
            return
        }
        if wasLit {
            withAnimation(Fluid.Motion.fast) { litRect = rect }
        } else {
            // A fresh visit fades in where the pointer is, instead of sliding over from where it last was.
            var still = Transaction(animation: nil)
            still.disablesAnimations = true
            withTransaction(still) { litRect = rect }
            withAnimation(.linear(duration: 0.08)) { litOpacity = 1 }
        }
    }
}

// MARK: Select

struct FluidOption<Value: Hashable>: Identifiable {
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

/// A button showing the current choice that opens a list of the others. Picking one springs the marker to it and
/// draws its check, and the list stays open 300 ms so that is seen before it closes.
struct FluidSelect<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [FluidOption<Value>]
    var placeholder = "Select…"
    var icon: String?
    var bordered = true
    var density: Fluid.Density = .compact
    var minWidth: CGFloat?

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.fluidSurfaceLevel) private var substrate
    @State private var open = false
    @State private var hovered = false
    @State private var closing: Task<Void, Never>?

    private var current: FluidOption<Value>? { options.first { $0.value == selection } }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Fluid.Radius.item, style: .continuous)
        Button {
            closing?.cancel()
            open.toggle()
        } label: {
            HStack(spacing: density.gap + 2) {
                if let icon = icon ?? current?.icon {
                    Image(systemName: icon)
                        .font(.system(size: density.icon - 2, weight: hovered ? .semibold : .regular))
                        .foregroundStyle(hovered ? Fluid.foreground : Fluid.mutedForeground)
                }
                Text(current?.title ?? placeholder)
                    .font(Fluid.font(.body, density: density))
                    .foregroundStyle(current == nil ? Fluid.mutedForeground : Fluid.foreground)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: density.icon - 4, weight: .semibold))
                    .foregroundStyle(hovered || open ? Fluid.foreground : Fluid.mutedForeground)
            }
            .padding(.horizontal, density.paddingX)
            .frame(minWidth: minWidth ?? (density == .compact ? 128 : 160))
            .frame(height: density.control)
            .background(hovered || open ? Fluid.hover : .clear, in: shape)
            .overlay(shape.strokeBorder(bordered ? Fluid.border : .clear, lineWidth: 1))
            .contentShape(shape)
            .animation(.easeOut(duration: 0.08), value: hovered)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovered = $0 && isEnabled }
        .opacity(isEnabled ? 1 : 0.5)
        .fluidPopup(isPresented: $open, matchWidth: true) {
            FluidPopupSurface(substrate: substrate) {
                ScrollView(.vertical) {
                    FluidMenuList(rows: options.map { option in
                        .item(option.title, icon: option.icon, checked: option.value == selection, id: AnyHashable(option.value)) {
                            pick(option.value)
                        }
                    }, density: density)
                }
                .scrollIndicators(.never)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .accessibilityRepresentation {
            Picker("", selection: $selection) {
                ForEach(options) { Text($0.title).tag($0.value) }
            }
        }
    }

    private func pick(_ value: Value) {
        selection = value
        closing?.cancel()
        closing = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            if !Task.isCancelled { open = false }
        }
    }
}

// MARK: Dropdown

/// A trigger that opens a menu of actions and choices. A pick closes it straight away.
struct FluidDropdown<Label: View>: View {
    let rows: () -> [FluidMenuRow]
    var density: Fluid.Density = .compact
    var width: CGFloat = 220
    var placement: FluidPopupPlacement = .below
    @ViewBuilder var label: (_ isOpen: Bool) -> Label

    @Environment(\.fluidSurfaceLevel) private var substrate
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: { label(open) }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .fluidPopup(isPresented: $open, placement: placement) {
                FluidPopupSurface(maxHeight: 480, substrate: substrate) {
                    ScrollView(.vertical) {
                        FluidMenuList(rows: rows().map { row in
                            var row = row
                            let action = row.action
                            row.action = { open = false; action() }
                            return row
                        }, density: density, boldChecked: true, reserveCheckSlot: false, lightFirstRow: true, minWidth: width - 8)
                    }
                    .scrollIndicators(.never)
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
    }
}
