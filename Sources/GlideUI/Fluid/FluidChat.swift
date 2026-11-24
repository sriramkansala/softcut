import AppKit
import SwiftUI

// Fluid Functionalism's ChatMessage and InputMessage (the chat composer). Ported from the MIT-licensed originals by
// Micka Touillaud. Attachments, queued messages and streaming are left out: nothing in Glide uses them.

enum FluidChatSender {
    case user, assistant
}

/// One message in a transcript. The user's sit in a bubble on the right; replies are plain text on the left. The time
/// and any actions wait under the message until it is hovered, in a row that always keeps its height.
struct FluidChatMessage<Actions: View>: View {
    let from: FluidChatSender
    let text: String
    var time: Date?
    var density: Fluid.Density = .compact
    @ViewBuilder var actions: Actions

    @State private var hovered = false

    private var isUser: Bool { from == .user }
    /// 55% accent and 45% background, mixed in OKLab.
    private static var bubble: Color { Color(fluidHex: 0x363636) }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            Text(text)
                .font(Fluid.font(.subtitle, density: density))
                .foregroundStyle(Fluid.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.horizontal, isUser ? (density == .compact ? 12 : 14) : 0)
                .padding(.vertical, density == .compact ? 6 : 8)
                .background {
                    if isUser { RoundedRectangle(cornerRadius: Fluid.Radius.item, style: .continuous).fill(Self.bubble) }
                }
            HStack(spacing: 8) {
                if isUser, let time {
                    Text(time, format: .dateTime.hour().minute()).font(Fluid.font(.caption, monospacedDigits: true))
                }
                actions
            }
            .foregroundStyle(Fluid.mutedForeground)
            .padding(.horizontal, 4)
            .frame(height: 16)
            .opacity(hovered ? 1 : 0)
            .allowsHitTesting(hovered)
            .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.15), value: hovered)
        }
        .containerRelativeFrame(.horizontal, alignment: isUser ? .trailing : .leading) { width, _ in width * 0.8 }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .onHover { hovered = $0 }
        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: isUser ? .bottomTrailing : .bottomLeading))
            .combined(with: .offset(y: 8)), removal: .identity))
    }
}

extension FluidChatMessage where Actions == EmptyView {
    init(from: FluidChatSender, text: String, time: Date? = nil, density: Fluid.Density = .compact) {
        self.init(from: from, text: text, time: time, density: density) { EmptyView() }
    }
}

/// The chat composer: a text area that grows with what is typed, an action bar with the send button, and suggested
/// prompts while it is empty. Return sends and Shift-Return starts a new line. ↑ and ↓ walk through what was sent
/// before; on an empty draft ↓ moves into the suggestions, and Return or a click puts the highlighted one in the draft.
struct FluidComposer<Leading: View>: View {
    @Binding var text: String
    var placeholder = "Ask me anything…"
    var suggestions: [String] = []
    /// What was sent before, oldest first.
    var history: [String] = []
    let onSend: (String) -> Void
    @ViewBuilder var leading: Leading

    @Environment(\.fluidSurfaceLevel) private var substrate
    @State private var isFocused = false
    @State private var hovered = false
    @State private var height: CGFloat = 30
    @State private var focusRequest = 0
    @State private var activeSuggestion: Int?
    @State private var hoveredSuggestion: Int?
    @State private var historyPlace: Int?
    @State private var stashedDraft = ""

    private var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var showsSuggestions: Bool { text.isEmpty && !suggestions.isEmpty }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Fluid.Radius.container, style: .continuous)
        VStack(spacing: 4) {
            ZStack(alignment: .topLeading) {
                FluidComposerText(text: $text, height: $height, placeholder: placeholder, focusRequest: focusRequest,
                                  onFocus: { isFocused = $0 }, onKey: handle)
                    .frame(height: height)
                if text.isEmpty {
                    Text(placeholder)
                        .font(Fluid.font(.subtitle))
                        .foregroundStyle(Fluid.mutedForeground)
                        .lineLimit(1)
                        .padding(6)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }

            HStack(spacing: 6) {
                leading
                Spacer(minLength: 0)
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Fluid.background)
                        .frame(width: 24, height: 24)
                        .background(Fluid.foreground, in: RoundedRectangle(cornerRadius: Fluid.Radius.item, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.5)
                .accessibilityLabel("Send")
            }

            if showsSuggestions { suggestionList.transition(.opacity) }
        }
        .padding(8)
        .fluidSurface(min(substrate + 1, 8), radius: Fluid.Radius.container)
        .overlay {
            if isFocused {
                shape.strokeBorder(Fluid.foreground.opacity(0.2), lineWidth: 1)
            } else if hovered {
                shape.strokeBorder(Fluid.border, lineWidth: 1)
            }
        }
        .contentShape(shape)
        .onTapGesture { focusRequest += 1 }
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.08), value: isFocused)
        .animation(.easeOut(duration: 0.08), value: hovered)
        .animation(Fluid.Motion.moderate, value: showsSuggestions)
        .onChange(of: text) { if !text.isEmpty { activeSuggestion = nil } }
    }

    private var suggestionList: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Fluid.border.opacity(0.6)).frame(height: 1).padding(.horizontal, -8)
            VStack(spacing: 0) {
                ForEach(suggestions.indices, id: \.self) { index in
                    let lit = activeSuggestion == index || (activeSuggestion == nil && hoveredSuggestion == index)
                    HStack(spacing: 8) {
                        Text(suggestions[index]).lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 0)
                        Image(systemName: "return")
                            .font(.system(size: 11))
                            .opacity(lit ? 1 : 0)
                    }
                    .font(Fluid.font(.subtitle))
                    .foregroundStyle(lit ? Fluid.foreground : Fluid.mutedForeground)
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(lit ? Fluid.hover : .clear, in: RoundedRectangle(cornerRadius: Fluid.Radius.item, style: .continuous))
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { hoveredSuggestion = index } else if hoveredSuggestion == index { hoveredSuggestion = nil }
                    }
                    .onTapGesture { fill(index) }
                    .animation(.easeOut(duration: 0.08), value: lit)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { fill(index) }
                }
            }
            .padding(.top, 6)
            .padding(.horizontal, -2)
        }
        .padding(.top, 4)
    }

    private func fill(_ index: Int) {
        text = suggestions[index]
        activeSuggestion = nil
        focusRequest += 1
    }

    private func send() {
        guard canSend else { return }
        onSend(text)
        text = ""
        historyPlace = nil
        stashedDraft = ""
        focusRequest += 1
    }

    private func handle(_ key: FluidComposerKey) -> Bool {
        switch key {
        case .submit:
            if let activeSuggestion, showsSuggestions { fill(activeSuggestion) } else { send() }
            return true
        case .up:
            if let active = activeSuggestion {
                activeSuggestion = active > 0 ? active - 1 : nil
                return true
            }
            guard !history.isEmpty, historyPlace != 0 else { return historyPlace == 0 }
            if historyPlace == nil { stashedDraft = text }
            let place = (historyPlace ?? history.count) - 1
            historyPlace = place
            text = history[place]
            return true
        case .down:
            if let place = historyPlace {
                if place + 1 < history.count {
                    historyPlace = place + 1
                    text = history[place + 1]
                } else {
                    historyPlace = nil
                    text = stashedDraft
                }
                return true
            }
            guard showsSuggestions else { return false }
            activeSuggestion = min((activeSuggestion ?? -1) + 1, suggestions.count - 1)
            return true
        case .escape:
            if activeSuggestion != nil {
                activeSuggestion = nil
                return true
            }
            return false
        }
    }
}

enum FluidComposerKey {
    case submit, up, down, escape
}

/// The composer's text area. It reports its height, between one row and eight, and scrolls past that.
struct FluidComposerText: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    let placeholder: String
    let focusRequest: Int
    let onFocus: (Bool) -> Void
    /// Returns whether the key was dealt with.
    let onKey: (FluidComposerKey) -> Bool

    private static let lineHeight: CGFloat = 18
    private static let inset: CGFloat = 6

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let view = ReportingTextView(frame: .zero)
        view.onFocus = { context.coordinator.parent.onFocus($0) }
        view.delegate = context.coordinator
        view.drawsBackground = false
        view.isRichText = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.font = .systemFont(ofSize: 13)
        view.textColor = NSColor(Fluid.foreground)
        view.insertionPointColor = NSColor(Fluid.foreground)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = Self.lineHeight
        paragraph.maximumLineHeight = Self.lineHeight
        view.defaultParagraphStyle = paragraph
        view.typingAttributes = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor(Fluid.foreground), .paragraphStyle: paragraph]
        view.textContainerInset = NSSize(width: Self.inset, height: Self.inset)
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        view.setAccessibilityLabel("Message")
        view.setAccessibilityPlaceholderValue(placeholder)

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = false
        scroll.documentView = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView else { return }
        if view.string != text {
            view.string = text
            view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            context.coordinator.reportHeight(of: view)
        }
        if context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
            DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        }
    }

    private final class ReportingTextView: NSTextView {
        var onFocus: (Bool) -> Void = { _ in }

        override func becomeFirstResponder() -> Bool {
            let became = super.becomeFirstResponder()
            if became { onFocus(true) }
            return became
        }

        override func resignFirstResponder() -> Bool {
            let resigned = super.resignFirstResponder()
            if resigned { onFocus(false) }
            return resigned
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: FluidComposerText
        var focusRequest: Int

        init(_ parent: FluidComposerText) {
            self.parent = parent
            focusRequest = parent.focusRequest
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
            reportHeight(of: view)
        }

        func reportHeight(of view: NSTextView) {
            guard let manager = view.layoutManager, let container = view.textContainer else { return }
            manager.ensureLayout(for: container)
            let rows = max(1, min(8, (manager.usedRect(for: container).height / lineHeight).rounded(.up)))
            let height = rows * lineHeight + FluidComposerText.inset * 2
            if height != parent.height {
                DispatchQueue.main.async { self.parent.height = height }
            }
        }

        private var lineHeight: CGFloat { FluidComposerText.lineHeight }

        func textView(_ view: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                if view.hasMarkedText() { return false }
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    view.insertNewlineIgnoringFieldEditor(nil)
                    return true
                }
                return parent.onKey(.submit)
            case #selector(NSResponder.moveUp(_:)):
                return caret(in: view).onFirstLine && parent.onKey(.up)
            case #selector(NSResponder.moveDown(_:)):
                return caret(in: view).onLastLine && parent.onKey(.down)
            case #selector(NSResponder.cancelOperation(_:)):
                if !parent.onKey(.escape) { view.window?.makeFirstResponder(nil) }
                return true
            case #selector(NSResponder.insertTab(_:)):
                view.window?.selectNextKeyView(nil)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                view.window?.selectPreviousKeyView(nil)
                return true
            default:
                return false
            }
        }

        private func caret(in view: NSTextView) -> (onFirstLine: Bool, onLastLine: Bool) {
            let length = (view.string as NSString).length
            guard length > 0, let manager = view.layoutManager, let container = view.textContainer else { return (true, true) }
            manager.ensureLayout(for: container)
            let place = view.selectedRange().location
            let line = manager.lineFragmentRect(forGlyphAt: manager.glyphIndexForCharacter(at: min(place, length - 1)), effectiveRange: nil)
            let first = manager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
            let last = manager.lineFragmentRect(forGlyphAt: manager.numberOfGlyphs - 1, effectiveRange: nil)
            // A caret after a final line break sits on a line of its own.
            let afterBreak = place == length && view.string.hasSuffix("\n")
            return (line.minY <= first.minY && !afterBreak, line.minY >= last.minY)
        }
    }
}
