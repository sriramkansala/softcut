import AppKit
import SwiftUI

// Fluid Functionalism's CheckboxGroup, RadioGroup, Accordion, InputGroup field, InputCopy, Table and ScrollArea.
// Ported from the MIT-licensed originals by Micka Touillaud.

// MARK: Row list scaffold

/// The shared list behaviour of checkbox and radio groups: the row nearest the pointer is lit by one sliding
/// highlight, chosen rows sit on `active` blocks, and a click in a gap goes to the lit row.
private struct FluidChoiceList<Row: View>: View {
    let ids: [AnyHashable]
    let chosen: Set<AnyHashable>
    /// Radio groups move one block between rows; checkbox groups join neighbouring chosen rows into one block.
    let joinsRuns: Bool
    let activate: (AnyHashable) -> Void
    @ViewBuilder var row: (AnyHashable, _ isLit: Bool) -> Row

    @State private var space = "fluid-choices-\(UUID().uuidString)"
    @State private var frames: [AnyHashable: CGRect] = [:]
    @State private var lit: AnyHashable?
    @State private var litRect: CGRect?
    @State private var litOpacity = 0.0

    var body: some View {
        VStack(spacing: 0) {
            ForEach(ids, id: \.self) { id in
                row(id, lit == id)
                    .contentShape(Rectangle())
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(space)) } action: { frames[id] = $0 }
                    .onTapGesture { activate(id) }
            }
        }
        .background(alignment: .topLeading) {
            let shape = RoundedRectangle(cornerRadius: Fluid.Radius.item, style: .continuous)
            ZStack(alignment: .topLeading) {
                ForEach(blocks, id: \.key) { block in
                    shape.fill(Fluid.active)
                        .frame(width: block.rect.width, height: block.rect.height)
                        .offset(x: block.rect.minX, y: block.rect.minY)
                        .transition(.opacity.animation(Fluid.Motion.moderateExit))
                }
                if let litRect {
                    shape.fill(Fluid.hover)
                        .frame(width: litRect.width, height: litRect.height)
                        .offset(x: litRect.minX, y: litRect.minY)
                        .opacity(litOpacity)
                }
            }
            .animation(Fluid.Motion.moderate, value: blocks.map(\.rect))
            .allowsHitTesting(false)
        }
        .coordinateSpace(name: space)
        .contentShape(Rectangle())
        .onContinuousHover(coordinateSpace: .named(space)) { phase in
            switch phase {
            case .active(let point):
                let id = ids.first { frames[$0].map { $0.minY <= point.y && point.y <= $0.maxY } ?? false }
                    ?? ids.min { abs((frames[$0]?.midY ?? .infinity) - point.y) < abs((frames[$1]?.midY ?? .infinity) - point.y) }
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
        .onTapGesture { if let lit { activate(lit) } }
    }

    /// The `active` blocks: one per chosen row for a radio group; one per run of neighbouring chosen rows for a
    /// checkbox group, keyed by the run's first row so a run that grows or shrinks springs instead of reappearing.
    private var blocks: [(key: AnyHashable, rect: CGRect)] {
        var result: [(AnyHashable, CGRect)] = []
        var runStart: AnyHashable?
        var runRect: CGRect?
        for id in ids {
            guard chosen.contains(id), let rect = frames[id] else {
                if let runStart, let runRect { result.append((runStart, runRect)) }
                runStart = nil
                runRect = nil
                continue
            }
            if joinsRuns, let current = runRect {
                runRect = current.union(rect)
            } else {
                if let runStart, let runRect { result.append((runStart, runRect)) }
                runStart = joinsRuns ? id : AnyHashable("radio-selection")
                runRect = rect
            }
        }
        if let runStart, let runRect { result.append((runStart, runRect)) }
        return result
    }
}

private struct FluidChoiceLabel: View {
    let title: String
    var detail: String?
    let isOn: Bool
    let isLit: Bool
    let density: Fluid.Density

    var body: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                Text(title).font(Fluid.font(.body, .semibold, density: density)).hidden()
                Text(title).font(Fluid.font(.body, isOn ? .semibold : .normal, density: density))
            }
            .foregroundStyle(isOn || isLit ? Fluid.foreground : Fluid.mutedForeground)
            .lineLimit(1)
            Spacer(minLength: 4)
            if let detail {
                Text(detail).font(Fluid.font(.caption, density: density, monospacedDigits: true)).foregroundStyle(Fluid.mutedForeground)
            }
        }
        .animation(.easeOut(duration: 0.08), value: isOn)
        .animation(.easeOut(duration: 0.08), value: isLit)
    }
}

// MARK: CheckboxGroup

struct FluidCheckItem: Identifiable {
    let id: String
    let title: String
    var detail: String?
    var isOn: Binding<Bool>
    var isDisabled = false
}

/// A list of checkboxes. A checked box has no fill: its border goes clear and the drawn check alone marks it, and
/// neighbouring checked rows share one background.
struct FluidCheckboxGroup: View {
    let items: [FluidCheckItem]
    var density: Fluid.Density = .compact

    var body: some View {
        FluidChoiceList(ids: items.map { AnyHashable($0.id) },
                        chosen: Set(items.filter { $0.isOn.wrappedValue }.map { AnyHashable($0.id) }),
                        joinsRuns: true,
                        activate: { id in
                            if let item = items.first(where: { AnyHashable($0.id) == id }), !item.isDisabled { item.isOn.wrappedValue.toggle() }
                        }) { id, lit in
            if let item = items.first(where: { AnyHashable($0.id) == id }) {
                let on = item.isOn.wrappedValue
                HStack(spacing: density.gap + 4) {
                    FluidCheckbox(isOn: on, isLit: lit, density: density)
                    FluidChoiceLabel(title: item.title, detail: item.detail, isOn: on, isLit: lit, density: density)
                }
                .padding(.horizontal, density.paddingX)
                .frame(height: density.control)
                .opacity(item.isDisabled ? 0.5 : 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(.isToggle)
                .accessibilityValue(on ? "checked" : "unchecked")
            }
        }
    }
}

struct FluidCheckbox: View {
    let isOn: Bool
    var isLit = false
    var density: Fluid.Density = .compact

    var body: some View {
        let box: CGFloat = density == .compact ? 14 : 16
        ZStack {
            RoundedRectangle(cornerRadius: density == .compact ? 4 : 5, style: .continuous)
                .strokeBorder(isOn ? .clear : (isLit ? Fluid.mutedForeground.opacity(0.75) : Fluid.border), lineWidth: 1.5)
                .frame(width: box, height: box)
                .animation(.easeOut(duration: 0.08), value: isLit)
                .animation(.easeOut(duration: 0.08), value: isOn)
            CheckStroke()
                .trim(from: 0, to: isOn ? 1 : 0)
                .stroke(Fluid.foreground, style: StrokeStyle(lineWidth: density == .compact ? 1.33 : 1.5, lineCap: .round, lineJoin: .round))
                .frame(width: box + 2, height: box + 2)
                .animation(isOn ? .easeOut(duration: 0.08) : .easeIn(duration: 0.04), value: isOn)
        }
        .frame(width: box, height: box)
    }

    private struct CheckStroke: Shape {
        func path(in rect: CGRect) -> Path {
            let s = rect.width / 24
            var path = Path()
            path.move(to: CGPoint(x: 6 * s, y: 12 * s))
            path.addLine(to: CGPoint(x: 10 * s, y: 16 * s))
            path.addLine(to: CGPoint(x: 18 * s, y: 8 * s))
            return path
        }
    }
}

// MARK: RadioGroup

/// A list of choices with round markers. The selected row's background springs from the old row to the new one,
/// and its dot pops in from 30%.
struct FluidRadioGroup<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [FluidOption<Value>]
    var details: [Value: String] = [:]
    var density: Fluid.Density = .compact

    var body: some View {
        FluidChoiceList(ids: options.map { AnyHashable($0.value) }, chosen: [AnyHashable(selection)], joinsRuns: false,
                        activate: { id in if let option = options.first(where: { AnyHashable($0.value) == id }) { selection = option.value } }) { id, lit in
            if let option = options.first(where: { AnyHashable($0.value) == id }) {
                let on = option.value == selection
                HStack(spacing: density.gap + 4) {
                    FluidRadioMark(isOn: on, isLit: lit, density: density)
                    FluidChoiceLabel(title: option.title, detail: details[option.value], isOn: on, isLit: lit, density: density)
                }
                .padding(.horizontal, density.paddingX)
                .frame(height: density.control)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

struct FluidRadioMark: View {
    let isOn: Bool
    var isLit = false
    var density: Fluid.Density = .compact

    var body: some View {
        let size: CGFloat = density == .compact ? 14 : 16
        ZStack {
            Circle()
                .strokeBorder(isOn ? .clear : (isLit ? Fluid.mutedForeground.opacity(0.75) : Fluid.border), lineWidth: 1.5)
            Circle()
                .fill(Fluid.foreground)
                .frame(width: density == .compact ? 7 : 8, height: density == .compact ? 7 : 8)
                .scaleEffect(isOn ? 1 : 0.3)
                .opacity(isOn ? 1 : 0)
                .animation(isOn ? Fluid.Motion.fast : .easeInOut(duration: 0.04), value: isOn)
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.08), value: isLit)
    }
}

// MARK: Accordion

/// A titled section that opens and closes. The open item sits on a faint accent tint, its title turns semibold, and
/// the chevron turns to point down; the body's opacity leads its height so it dissolves rather than being sliced.
struct FluidAccordionItem<Content: View>: View {
    let title: String
    @Binding var isOpen: Bool
    var density: Fluid.Density = .compact
    var tinted = true
    @ViewBuilder var content: Content

    @State private var hovered = false

    var body: some View {
        let compact = density == .compact
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(isOpen ? .easeInOut(duration: 0.06) : Fluid.Motion.fast) { isOpen.toggle() }
            } label: {
                HStack(spacing: density.gap + 2) {
                    ZStack(alignment: .leading) {
                        Text(title).font(Fluid.font(.body, .semibold, density: density)).hidden()
                        Text(title).font(Fluid.font(.body, isOpen ? .semibold : .normal, density: density))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.system(size: compact ? 10 : 11, weight: isOpen || hovered ? .semibold : .regular))
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .animation(Fluid.Motion.fast, value: isOpen)
                }
                .foregroundStyle(isOpen || hovered ? Fluid.foreground : Fluid.mutedForeground)
                .padding(.horizontal, density.paddingX)
                .padding(.vertical, compact ? 4 : 8)
                .background(hovered ? Fluid.hover : .clear, in: RoundedRectangle(cornerRadius: Fluid.Radius.item, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .onHover { inside in withAnimation(.linear(duration: inside ? 0.08 : 0.06)) { hovered = inside } }
            .accessibilityValue(isOpen ? "expanded" : "collapsed")

            content
                .padding(.horizontal, density.paddingX)
                .padding(.top, 4)
                .padding(.bottom, compact ? 10 : 12)
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: isOpen ? nil : 0, alignment: .top)
                // Only what is folded away is cut off, with room left for an outline around what comes first.
                .mask { Rectangle().padding(-6) }
                .opacity(isOpen ? 1 : 0)
                .animation(isOpen ? .easeInOut(duration: 0.06) : .easeInOut(duration: 0.04), value: isOpen)
                .allowsHitTesting(isOpen)
                .accessibilityHidden(!isOpen)
        }
        .background {
            if tinted && isOpen {
                RoundedRectangle(cornerRadius: Fluid.Radius.item, style: .continuous).fill(Fluid.accent.opacity(0.12))
                    .transition(.opacity.animation(.easeInOut(duration: 0.12)))
            }
        }
    }
}

// MARK: InputGroup field

/// A frameless text field that lifts onto a card surface when focused and shows a faint fill and ring when the
/// pointer is near. The label never changes; only the icon brightens.
struct FluidInputField: View {
    var label: String?
    let placeholder: String
    @Binding var text: String
    var icon: String?
    var error: String?
    var multiline = false
    var density: Fluid.Density = .compact
    var onCommit: () -> Void = {}

    @FocusState private var focused: Bool
    @State private var hovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let compact = density == .compact
        let shape = RoundedRectangle(cornerRadius: Fluid.Radius.item, style: .continuous)
        let background: Color = focused ? Fluid.card : (hovered ? (error == nil ? Fluid.muted.opacity(0.5) : Fluid.destructiveLight.opacity(0.6)) : .clear)
        let ring: Color = error != nil ? (focused || hovered ? Fluid.destructive.opacity(0.5) : .clear) : (focused || hovered ? Fluid.border : .clear)
        VStack(alignment: .leading, spacing: 4) {
            if let label {
                Text(label)
                    .font(Fluid.font(.body, density: density))
                    .foregroundStyle(error == nil ? Fluid.mutedForeground : Fluid.destructive)
                    .padding(.leading, compact ? 8 : 10)
            }
            HStack(alignment: multiline ? .top : .center, spacing: density.gap + 2) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: density.icon - 2, weight: focused || hovered ? .semibold : .regular))
                        .foregroundStyle(focused || hovered ? Fluid.foreground : Fluid.mutedForeground)
                        .padding(.top, multiline ? 5 : 0)
                }
                TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Fluid.mutedForeground),
                          axis: multiline ? .vertical : .horizontal)
                    .textFieldStyle(.plain)
                    .font(Fluid.font(.body, density: density))
                    .foregroundStyle(Fluid.foreground)
                    .focused($focused)
                    .onSubmit(onCommit)
                    .padding(.vertical, multiline ? 5 : 0)
            }
            .padding(.horizontal, compact ? 8 : 10)
            .frame(minHeight: density.control)
            .background(background, in: shape)
            .overlay(RoundedRectangle(cornerRadius: Fluid.Radius.item + 1, style: .continuous).strokeBorder(ring, lineWidth: 1).padding(-1))
            .contentShape(shape)
            .onTapGesture { focused = true }
            .onHover { hovered = $0 && isEnabled }
            .animation(.easeOut(duration: 0.08), value: focused)
            .animation(.easeOut(duration: 0.08), value: hovered)
            if let error {
                Text(error).font(Fluid.font(.caption, density: density)).foregroundStyle(Fluid.destructive)
                    .padding(.leading, compact ? 8 : 10)
            }
        }
        .opacity(isEnabled ? 1 : 0.5)
    }
}

// MARK: InputCopy

/// A value with a copy action and no field chrome. Hovering marks the text like a selection; copying swaps the
/// icon for a check that draws in, for two seconds.
struct FluidInputCopy: View {
    var label: String?
    let value: String
    var density: Fluid.Density = .compact

    @State private var hovered = false
    @State private var copied = false
    @State private var copies = 0
    @State private var reset: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let label {
                Text(label).font(Fluid.font(.body, density: density)).foregroundStyle(Fluid.mutedForeground)
            }
            Button(action: copy) {
                HStack(spacing: 0) {
                    Text(value)
                        .font(.system(size: density == .compact ? 12 : 13, design: .monospaced))
                        .foregroundStyle(Fluid.foreground)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .background(hovered ? Fluid.focusRing.opacity(0.2) : .clear)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ZStack {
                        if copied {
                            FluidCheckmark(isOn: true, size: 14)
                                .id(copies)
                                .transition(.scale(scale: 0.6).combined(with: .opacity).animation(Fluid.Motion.fast))
                        } else {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 12, weight: hovered ? .semibold : .regular))
                                .foregroundStyle(hovered ? Fluid.foreground : Fluid.mutedForeground)
                                .transition(.scale(scale: 0.8).combined(with: .opacity).animation(Fluid.Motion.fast))
                        }
                    }
                    .frame(width: 14, height: 14)
                    .padding(.horizontal, 6)
                }
                .padding(.vertical, density == .compact ? 4 : 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.08), value: hovered)
            .fluidTooltip(copied ? "Copied" : "Copy to clipboard")
            .accessibilityLabel(copied ? "Copied" : "Copy \(label ?? value)")
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copies += 1
        withAnimation(Fluid.Motion.fast) { copied = true }
        reset?.cancel()
        reset = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { withAnimation(Fluid.Motion.fast) { copied = false } }
        }
    }
}

// MARK: Table

/// A plain table: each row ruled underneath at 40% accent, one square hover highlight springing between body rows,
/// and the rules either side of the lit row fading away. Body text is muted until its row is lit.
struct FluidTable: View {
    let columns: [String]
    let rows: [[String]]
    var density: Fluid.Density = .compact

    @State private var space = "fluid-table-\(UUID().uuidString)"
    @State private var frames: [Int: CGRect] = [:]
    @State private var lit: Int?
    @State private var litRect: CGRect?
    @State private var litOpacity = 0.0

    var body: some View {
        let compact = density == .compact
        let padding = EdgeInsets(top: compact ? 5 : 8, leading: compact ? 10 : 12, bottom: compact ? 5 : 8, trailing: compact ? 10 : 12)
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            if !columns.isEmpty {
                GridRow {
                    ForEach(Array(columns.enumerated()), id: \.offset) { column, title in
                        Text(title).font(Fluid.font(.body, .semibold, density: density)).foregroundStyle(Fluid.foreground)
                            .padding(padding)
                            .frame(maxWidth: .infinity, alignment: column == 0 ? .leading : .trailing)
                    }
                }
                .overlay(alignment: .bottom) { rule(hidden: lit == 0) }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { index, cells in
                GridRow {
                    ForEach(Array(cells.enumerated()), id: \.offset) { column, cell in
                        Text(cell)
                            .font(Fluid.font(.body, density: density, monospacedDigits: column > 0))
                            .foregroundStyle(lit == index ? Fluid.foreground : Fluid.mutedForeground)
                            .lineLimit(1)
                            .padding(padding)
                            .frame(maxWidth: .infinity, alignment: column == 0 ? .leading : .trailing)
                    }
                }
                .background { Color.clear.onGeometryChange(for: CGRect.self) { $0.frame(in: .named(space)) } action: { frames[index] = $0 } }
                .overlay(alignment: .bottom) { rule(hidden: lit == index || lit == index + 1 || index == rows.count - 1) }
            }
        }
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.08), value: lit)
        .background(alignment: .topLeading) {
            if let litRect {
                Rectangle().fill(Fluid.hover)
                    .frame(width: litRect.width, height: litRect.height)
                    .offset(x: litRect.minX, y: litRect.minY)
                    .opacity(litOpacity)
            }
        }
        .coordinateSpace(name: space)
        .onContinuousHover(coordinateSpace: .named(space)) { phase in
            switch phase {
            case .active(let point):
                let index = frames.first { $0.value.minY <= point.y && point.y <= $0.value.maxY }?.key
                guard index != lit else { return }
                lit = index
                guard let index, let rect = frames[index] else {
                    withAnimation(Fluid.Motion.fastExit) { litOpacity = 0 }
                    return
                }
                if litOpacity == 0 {
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
    }

    private func rule(hidden: Bool) -> some View {
        Rectangle().fill(Fluid.accent.opacity(0.4)).frame(height: 1).opacity(hidden ? 0 : 1)
    }
}

// MARK: ScrollArea

/// A vertical scroll view with Fluid's scrollbar: no track, a 4 pt thumb at 8% that widens to 6 pt and darkens under
/// the pointer, shown while hovered or for 600 ms after scrolling.
struct FluidScrollArea<Content: View>: View {
    /// Keeps the end in view when the content grows or the area shrinks, for a transcript.
    var followsBottom = false
    @ViewBuilder var content: Content

    @State private var geometry = ScrollGeometry(contentOffset: .zero, contentSize: .zero, contentInsets: EdgeInsets(),
                                                 containerSize: .zero)
    @State private var hovered = false
    @State private var thumbHovered = false
    @State private var recentlyScrolled = false
    @State private var hideTask: Task<Void, Never>?
    @State private var dragStart: CGFloat?
    @State private var position = ScrollPosition(edge: .top)
    @State private var followTask: Task<Void, Never>?

    var body: some View {
        ScrollView(.vertical) { content }
            .scrollIndicators(.never)
            .scrollPosition($position)
            .onScrollGeometryChange(for: ScrollGeometry.self) { $0 } action: { old, new in
                geometry = new
                if abs(old.contentOffset.y - new.contentOffset.y) > 0.5 {
                    recentlyScrolled = true
                    hideTask?.cancel()
                    hideTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(600))
                        if !Task.isCancelled { recentlyScrolled = false }
                    }
                }
            }
            .overlay(alignment: .topTrailing) { thumb }
            .onHover { hovered = $0 }
            .onChange(of: geometry.contentSize.height) { old, _ in scrollToEnd(animated: old > 0) }
            .onChange(of: geometry.containerSize.height) { scrollToEnd(animated: true) }
    }

    private func scrollToEnd(animated: Bool) {
        guard followsBottom else { return }
        // New content can change the size more than once as it settles, so this waits for the last change.
        followTask?.cancel()
        followTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(30))
            guard !Task.isCancelled else { return }
            // By distance, not by edge: asking for the same edge a second time would do nothing.
            let end = max(0, geometry.contentSize.height - geometry.containerSize.height)
            withAnimation(animated ? Fluid.Motion.moderate : nil) { position.scrollTo(y: end) }
        }
    }

    @ViewBuilder
    private var thumb: some View {
        let visible = geometry.containerSize.height
        let total = geometry.contentSize.height
        if total > visible + 1, visible > 0 {
            let track = visible - 4
            let length = max(24, track * visible / total)
            let progress = min(max(geometry.contentOffset.y / (total - visible), 0), 1)
            let shown = hovered || recentlyScrolled || dragStart != nil
            Capsule()
                .fill(Color.white.opacity(dragStart != nil ? 0.16 : (thumbHovered ? 0.12 : 0.08)))
                .frame(width: thumbHovered || dragStart != nil ? 6 : 4, height: length)
                .frame(width: 10, alignment: .center)
                .contentShape(Rectangle())
                .offset(y: 2 + (track - length) * progress)
                .opacity(shown ? 1 : 0)
                .animation(.easeOut(duration: 0.15), value: shown)
                .animation(.easeOut(duration: 0.1), value: thumbHovered)
                .onHover { thumbHovered = $0 }
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if dragStart == nil { dragStart = geometry.contentOffset.y }
                        let perPoint = (total - visible) / max(1, track - length)
                        let y = min(max((dragStart ?? 0) + drag.translation.height * perPoint, 0), total - visible)
                        position.scrollTo(y: y)
                    }
                    .onEnded { _ in dragStart = nil })
        }
    }
}
