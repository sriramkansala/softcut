import AppKit
import SwiftUI

// Fluid Functionalism's Dialog, CommandMenu and Combobox. Ported from the MIT-licensed originals by Micka Touillaud.

// MARK: Key-aware text field

/// A borderless text field that hands ↑, ↓, Return and Escape to its owner, for lists driven from a search field.
struct FluidKeyField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var font: NSFont = .systemFont(ofSize: 13)
    var focusOnAppear = true
    var onMove: (_ down: Bool) -> Void = { _ in }
    var onSubmit: () -> Void = {}
    var onCancel: () -> Void = {}
    var onFocus: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = FocusReportingField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = font
        field.textColor = NSColor(Fluid.foreground)
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .foregroundColor: NSColor(Fluid.mutedForeground), .font: font,
        ])
        field.delegate = context.coordinator
        field.onFocus = { context.coordinator.parent.onFocus($0) }
        field.cell?.lineBreakMode = .byTruncatingTail
        if focusOnAppear {
            DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    final class FocusReportingField: NSTextField {
        var onFocus: (Bool) -> Void = { _ in }
        override func becomeFirstResponder() -> Bool {
            let became = super.becomeFirstResponder()
            if became { onFocus(true) }
            return became
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FluidKeyField
        init(_ parent: FluidKeyField) { self.parent = parent }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidEndEditing(_ obj: Notification) { parent.onFocus(false) }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)): parent.onMove(false); return true
            case #selector(NSResponder.moveDown(_:)): parent.onMove(true); return true
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit(); return true
            case #selector(NSResponder.cancelOperation(_:)): parent.onCancel(); return true
            default: return false
            }
        }
    }
}

// MARK: Dialog

enum FluidDialogSize {
    case small, large, extraLarge
    var maxWidth: CGFloat {
        switch self {
        case .small: return 400
        case .large: return 540
        case .extraLarge: return 880
        }
    }
}

extension View {
    /// Fluid's dialog, drawn inside the window: a dark scrim, and a panel four surface levels up that grows from 97%
    /// on the slow spring. Escape or a click on the scrim closes it.
    func fluidDialog<Content: View, Footer: View>(isPresented: Binding<Bool>, title: String, description: String? = nil,
                                                 size: FluidDialogSize = .small,
                                                 @ViewBuilder content: @escaping () -> Content,
                                                 @ViewBuilder footer: @escaping () -> Footer) -> some View {
        modifier(FluidDialogModifier(isPresented: isPresented, size: size, showsClose: true) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(Fluid.font(.title, .semibold, density: .regular)).foregroundStyle(Fluid.foreground)
                    if let description {
                        Text(description).font(Fluid.font(.body, density: .regular)).foregroundStyle(Fluid.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.trailing, 28)
                .padding(.bottom, 16)
                content()
                HStack(spacing: 8) {
                    Spacer()
                    footer()
                }
                .padding(.top, 24)
            }
            .padding(24)
        })
    }

    /// A dialog shell for custom panels such as the command menu.
    func fluidDialogShell<Content: View>(isPresented: Binding<Bool>, size: FluidDialogSize = .large, alignTop: Bool = false,
                                         @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(FluidDialogModifier(isPresented: isPresented, size: size, showsClose: false, alignTop: alignTop, panel: content))
    }
}

private struct FluidDialogModifier<Panel: View>: ViewModifier {
    @Binding var isPresented: Bool
    let size: FluidDialogSize
    let showsClose: Bool
    var alignTop = false
    @ViewBuilder var panel: () -> Panel

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { proxy in
                    ZStack(alignment: alignTop ? .top : .center) {
                        if isPresented {
                            Color.black.opacity(0.8)
                                .ignoresSafeArea()
                                .contentShape(Rectangle())
                                .onTapGesture { close() }
                                .transition(.asymmetric(insertion: .opacity.animation(Fluid.Motion.slow),
                                                        removal: .opacity.animation(Fluid.Motion.slowExit)))
                            panel()
                                .frame(maxWidth: min(size.maxWidth, proxy.size.width - 32))
                                .fixedSize(horizontal: false, vertical: true)
                                .environment(\.fluidSurfaceLevel, 5)
                                .fluidSurface(5, radius: Fluid.Radius.container)
                                .overlay(alignment: .topTrailing) {
                                    if showsClose {
                                        FluidIconButton(systemName: "xmark", help: "Close") { close() }.padding(12)
                                    }
                                }
                                .padding(.top, alignTop ? max(proxy.size.height * 0.12, proxy.size.height / 2 - 220) : 0)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.97).combined(with: .opacity).animation(Fluid.Motion.slow),
                                    removal: .scale(scale: 0.97).combined(with: .opacity).animation(Fluid.Motion.slowExit)))
                                .onExitCommand { close() }
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: alignTop ? .top : .center)
                }
            }
    }

    private func close() { isPresented = false }
}

// MARK: Shortcut caps

/// Keyboard keys drawn as small caps, one per glyph: "⌘⇧P" becomes three.
struct FluidShortcutCaps: View {
    let keys: String
    var density: Fluid.Density = .regular

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(glyphs.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(Fluid.font(.micro, density: density))
                    .foregroundStyle(Fluid.mutedForeground)
                    .padding(.horizontal, 4)
                    .frame(minWidth: density == .compact ? 16 : 20, minHeight: density == .compact ? 16 : 20)
                    .background(Fluid.hover, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
    }

    private var glyphs: [String] {
        if ["Esc", "Space", "Tab"].contains(keys) { return [keys] }
        return keys.map { String($0).uppercased() }
    }
}

// MARK: CommandMenu

struct FluidCommand: Identifiable {
    let id: String
    var title: String
    var detail: String?
    var icon: String?
    var section: String
    var shortcut: String?
    var keywords: [String] = []
    var isEnabled = true
    var action: () -> Void
}

/// A palette of commands: a search field, the matching commands in sections, and a footer of key hints with the lit
/// command's name. The panel's height springs to fit its rows as you type, and the keyboard keeps the lit row
/// centred.
struct FluidCommandMenu: View {
    let commands: [FluidCommand]
    var placeholder = "Type a command or search…"
    let close: () -> Void

    @State private var query = ""
    @State private var lit: String?
    @State private var space = "fluid-command-\(UUID().uuidString)"
    @State private var frames: [String: CGRect] = [:]
    @State private var litRect: CGRect?
    @State private var listHeight: CGFloat = 0
    @State private var position = ScrollPosition(idType: String.self)

    private var matches: [FluidCommand] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return commands }
        return commands.filter { command in
            let haystack = ([command.title, command.detail ?? ""] + command.keywords).joined(separator: " ").lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
    }

    private var sections: [(String, [FluidCommand])] {
        var order: [String] = []
        var grouped: [String: [FluidCommand]] = [:]
        for command in matches {
            if grouped[command.section] == nil { order.append(command.section) }
            grouped[command.section, default: []].append(command)
        }
        return order.map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .medium)).foregroundStyle(Fluid.foreground)
                FluidKeyField(text: $query, placeholder: placeholder, font: .systemFont(ofSize: 14),
                              onMove: move, onSubmit: run, onCancel: close)
                    .frame(height: 24)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            Rectangle().fill(Fluid.divider).frame(height: 1)
            ScrollView(.vertical) {
                if matches.isEmpty {
                    Text("Nothing matches “\(query)”")
                        .font(Fluid.font(.body, density: .regular)).foregroundStyle(Fluid.mutedForeground)
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                } else {
                    list
                }
            }
            .scrollIndicators(.never)
            .scrollPosition($position, anchor: .center)
            .frame(height: min(listHeight, 330))
            .animation(Fluid.Motion.moderate, value: listHeight)
            Rectangle().fill(Fluid.divider).frame(height: 1)
            footer
        }
        .onChange(of: matches.map(\.id)) { _, ids in
            lit = matches.first { $0.isEnabled }?.id
            var still = Transaction(animation: nil)
            still.disablesAnimations = true
            withTransaction(still) { litRect = lit.flatMap { frames[$0] } }
            position.scrollTo(edge: .top)
            _ = ids
        }
        .onAppear { lit = matches.first { $0.isEnabled }?.id }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(sections, id: \.0) { section, items in
                VStack(alignment: .leading, spacing: 0) {
                    Text(section)
                        .font(Fluid.font(.caption, density: .regular))
                        .foregroundStyle(Fluid.mutedForeground)
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                    ForEach(items) { command in row(command) }
                }
            }
        }
        .padding(4)
        .background(alignment: .topLeading) {
            if let rect = litRect ?? lit.flatMap({ frames[$0] }) {
                RoundedRectangle(cornerRadius: Fluid.Radius.item, style: .continuous).fill(Fluid.hover)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .allowsHitTesting(false)
            }
        }
        .coordinateSpace(name: space)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
        .onContinuousHover(coordinateSpace: .named(space)) { phase in
            // The lit row stays lit when the pointer leaves, so Return always has a target.
            guard case .active(let point) = phase else { return }
            let candidates = matches.filter { $0.isEnabled }
            let id = candidates.first { frames[$0.id].map { $0.minY <= point.y && point.y <= $0.maxY } ?? false }?.id
                ?? candidates.min { abs((frames[$0.id]?.midY ?? .infinity) - point.y) < abs((frames[$1.id]?.midY ?? .infinity) - point.y) }?.id
            if let id, id != lit { light(id, scroll: false) }
        }
    }

    private func row(_ command: FluidCommand) -> some View {
        let on = lit == command.id
        return HStack(spacing: 8) {
            if let icon = command.icon {
                Image(systemName: icon).font(.system(size: 13, weight: on ? .semibold : .regular)).frame(width: 16)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(command.title).lineLimit(1)
                if let detail = command.detail { Text(detail).foregroundStyle(Fluid.mutedForeground).lineLimit(1) }
            }
            Spacer(minLength: 8)
            if let shortcut = command.shortcut { FluidShortcutCaps(keys: shortcut) }
        }
        .font(Fluid.font(.body, density: .regular))
        .foregroundStyle(on ? Fluid.foreground : Fluid.mutedForeground)
        .animation(.easeOut(duration: 0.08), value: on)
        .padding(.horizontal, 8)
        .frame(height: 36)
        .contentShape(Rectangle())
        .opacity(command.isEnabled ? 1 : 0.5)
        .id(command.id)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(space)) } action: { frames[command.id] = $0 }
        .onTapGesture { if command.isEnabled { lit = command.id; run() } }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            hint("Select", "↑↓")
            hint("Close", "Esc")
            Spacer(minLength: 8)
            if let command = commands.first(where: { $0.id == lit }) {
                HStack(spacing: 6) {
                    Text(command.title).foregroundStyle(Fluid.foreground).lineLimit(1)
                    FluidShortcutCaps(keys: "↵")
                }
            }
        }
        .font(Fluid.font(.caption, density: .regular))
        .foregroundStyle(Fluid.mutedForeground)
        .padding(.horizontal, 16)
        .frame(height: 40)
    }

    private func hint(_ label: String, _ keys: String) -> some View {
        HStack(spacing: 6) { Text(label); FluidShortcutCaps(keys: keys) }
    }

    private func light(_ id: String, scroll: Bool) {
        let fresh = litRect == nil
        lit = id
        if fresh {
            litRect = frames[id]
        } else {
            withAnimation(Fluid.Motion.fast) { litRect = frames[id] }
        }
        if scroll { withAnimation(Fluid.Motion.fast) { position.scrollTo(id: id) } }
    }

    private func move(_ down: Bool) {
        let enabled = matches.filter { $0.isEnabled }
        guard !enabled.isEmpty else { return }
        let index = enabled.firstIndex { $0.id == lit } ?? (down ? -1 : enabled.count)
        let next = (index + (down ? 1 : -1) + enabled.count) % enabled.count
        light(enabled[next].id, scroll: true)
    }

    private func run() {
        guard let command = matches.first(where: { $0.id == lit }), command.isEnabled else { return }
        close()
        DispatchQueue.main.async { command.action() }
    }
}

// MARK: Combobox

/// A text field that filters a list of options as you type. The first match is lit as soon as the list opens, so
/// Return always picks something; Escape puts back the chosen option's name.
struct FluidCombobox<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [FluidOption<Value>]
    var placeholder = "Search…"
    var icon: String? = "magnifyingglass"
    var density: Fluid.Density = .compact

    @Environment(\.fluidSurfaceLevel) private var substrate
    @State private var query = ""
    @State private var editing = false
    @State private var open = false
    @State private var hovered = false
    @State private var lit: Value?

    private var matches: [FluidOption<Value>] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard editing, !words.isEmpty else { return options }
        return options.filter { option in words.allSatisfy { option.title.lowercased().contains($0) } }
    }

    private var current: FluidOption<Value>? { options.first { $0.value == selection } }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Fluid.Radius.item, style: .continuous)
        let compact = density == .compact
        HStack(spacing: density.gap + 2) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: density.icon - 2, weight: editing ? .semibold : .regular))
                    .foregroundStyle(editing ? Fluid.foreground : Fluid.mutedForeground)
            }
            FluidKeyField(text: Binding(get: { editing ? query : (current?.title ?? "") },
                                        set: { query = $0; editing = true; open = true; lit = matches.first?.value }),
                          placeholder: placeholder, font: .systemFont(ofSize: compact ? 12 : 13), focusOnAppear: false,
                          onMove: move, onSubmit: pick, onCancel: cancel,
                          onFocus: { focused in
                              if focused {
                                  editing = true
                                  query = ""
                                  open = true
                                  lit = selection
                              } else if !open {
                                  editing = false
                              }
                          })
                .frame(height: 20)
            Image(systemName: "chevron.down")
                .font(.system(size: density.icon - 4, weight: .semibold))
                .foregroundStyle(hovered ? Fluid.foreground : Fluid.mutedForeground)
                .frame(width: compact ? 20 : 24, height: compact ? 20 : 24)
                .contentShape(Rectangle())
                .onTapGesture { open.toggle(); if open { lit = selection } }
        }
        .padding(.horizontal, compact ? 8 : 10)
        .frame(minWidth: compact ? 128 : 160)
        .frame(height: density.control)
        .background(editing ? Fluid.card : (hovered ? Fluid.muted.opacity(0.5) : .clear), in: shape)
        .overlay(RoundedRectangle(cornerRadius: Fluid.Radius.item + 0.5, style: .continuous).strokeBorder(Fluid.border, lineWidth: 1).padding(-0.5))
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.08), value: editing)
        .fluidPopup(isPresented: Binding(get: { open }, set: { now in open = now; if !now { editing = false; query = "" } }),
                    matchWidth: true, takesKey: false) {
            FluidPopupSurface(substrate: substrate) {
                if matches.isEmpty {
                    Text("No matches").font(Fluid.font(.body, density: density)).foregroundStyle(Fluid.mutedForeground)
                        .frame(maxWidth: .infinity).padding(.vertical, 20)
                } else {
                    ScrollView(.vertical) {
                        FluidMenuList(rows: matches.map { option in
                            .item(option.title, icon: option.icon, checked: option.value == selection, id: AnyHashable(option.value)) {
                                selection = option.value
                                finish()
                            }
                        }, density: density)
                    }
                    .scrollIndicators(.never)
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
        }
    }

    private func move(_ down: Bool) {
        if !open { open = true; lit = down ? matches.first?.value : matches.last?.value; return }
        guard !matches.isEmpty else { return }
        let index = matches.firstIndex { $0.value == lit } ?? (down ? -1 : matches.count)
        lit = matches[(index + (down ? 1 : -1) + matches.count) % matches.count].value
        if let lit { selection = lit }
    }

    private func pick() {
        if let value = lit ?? matches.first?.value { selection = value }
        finish()
    }

    private func cancel() { finish() }

    private func finish() {
        open = false
        editing = false
        query = ""
        NSApp.keyWindow?.makeFirstResponder(nil)
    }
}
