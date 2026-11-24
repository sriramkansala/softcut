import AppKit
import SwiftUI

// Fluid Functionalism popups (dropdowns, selects, comboboxes, color pickers), in a borderless panel of their own so
// they can float over everything with Fluid's surface, shadow and motion instead of a system popover's chrome.

enum FluidPopupPlacement {
    /// Under the trigger, left edges lined up (flipped above if there is no room below).
    case below
    /// Under the trigger, right edges lined up.
    case belowTrailing
    /// Above the trigger.
    case above
    /// To the left of the trigger, centred on it.
    case leading
}

extension View {
    /// Shows `content` in a floating popup anchored to this view while `isPresented` is true. A click outside it or
    /// Escape closes it. `matchWidth` makes it at least as wide as the trigger. A popup that isn't `interactive` (a
    /// tooltip) never takes the keyboard or the mouse. `inset` is the transparent margin the content leaves around
    /// its visible surface for shadows.
    func fluidPopup<Content: View>(isPresented: Binding<Bool>, placement: FluidPopupPlacement = .below, offset: CGFloat = 6,
                                   matchWidth: Bool = false, interactive: Bool = true, takesKey: Bool = true,
                                   inset: CGFloat = FluidPopupSurface<EmptyView>.shadowRoom,
                                   @ViewBuilder content: @escaping () -> Content) -> some View {
        background(FluidPopupAnchor(isPresented: isPresented, placement: placement, offset: offset, matchWidth: matchWidth,
                                    interactive: interactive, takesKey: takesKey, inset: inset, content: { AnyView(content()) }))
    }
}

private struct FluidPopupOpensUpKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True inside a popup that opened above its trigger.
    var fluidPopupOpensUp: Bool {
        get { self[FluidPopupOpensUpKey.self] }
        set { self[FluidPopupOpensUpKey.self] = newValue }
    }
}

private struct FluidPopupAnchor: NSViewRepresentable {
    @Binding var isPresented: Bool
    let placement: FluidPopupPlacement
    let offset: CGFloat
    let matchWidth: Bool
    let interactive: Bool
    let takesKey: Bool
    let inset: CGFloat
    let content: () -> AnyView

    func makeCoordinator() -> FluidPopupController { FluidPopupController() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.anchor = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        let controller = context.coordinator
        controller.onDismiss = { isPresented = false }
        if isPresented {
            controller.present(content: content(), placement: placement, offset: offset, matchWidth: matchWidth,
                               interactive: interactive, takesKey: takesKey, inset: inset)
        } else {
            controller.dismiss()
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: FluidPopupController) {
        coordinator.dismiss(animated: false)
    }
}

/// Owns one popup panel: shows it next to its anchor, keeps its content current, and closes it on an outside click,
/// Escape, or the anchor's window going away.
@MainActor
final class FluidPopupController: NSObject {
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    weak var anchor: NSView?
    var onDismiss: (() -> Void)?
    private var panel: Panel?
    private var host: NSHostingView<AnyView>?
    private var monitors: [Any] = []
    private var closing = false
    private var opensUp = false
    private var inset: CGFloat = 14

    func present(content: AnyView, placement: FluidPopupPlacement, offset: CGFloat, matchWidth: Bool,
                 interactive: Bool = true, takesKey: Bool = true, inset: CGFloat = 14) {
        guard let anchor, let window = anchor.window else { return }
        self.inset = inset
        let triggerRect = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        func rooted(up: Bool) -> AnyView {
            AnyView(content.environment(\.colorScheme, .dark).environment(\.fluidPopupOpensUp, up))
        }

        if let host, let panel {
            // Already open: refresh what it shows and keep it in place.
            host.rootView = rooted(up: opensUp)
            position(panel, size: host.fittingSize, trigger: triggerRect, placement: placement, offset: offset, matchWidth: matchWidth)
            return
        }

        let host = NSHostingView(rootView: rooted(up: false))
        host.sizingOptions = [.intrinsicContentSize]
        let panel = Panel(contentRect: CGRect(origin: .zero, size: host.fittingSize), styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = !interactive
        // A popup that leaves the keyboard with its trigger (a combobox's list) only takes it for a text field.
        panel.becomesKeyOnlyIfNeeded = !takesKey
        opensUp = position(panel, size: host.fittingSize, trigger: triggerRect, placement: placement, offset: offset, matchWidth: matchWidth)
        if opensUp { host.rootView = rooted(up: true) }
        panel.alphaValue = 1
        window.addChildWindow(panel, ordered: .above)
        self.panel = panel
        self.host = host
        closing = false
        if interactive {
            if takesKey { panel.makeKey() }
            installMonitors()
        }
    }

    /// Places the panel so its visible surface (inset by the shadow room on every side) sits `offset` from the
    /// trigger. Returns whether it opened upward.
    @discardableResult
    private func position(_ panel: NSPanel, size: CGSize, trigger: CGRect, placement: FluidPopupPlacement, offset: CGFloat, matchWidth: Bool) -> Bool {
        let room = inset
        var size = size
        if matchWidth { size.width = max(size.width, trigger.width + room * 2) }
        let screen = (anchor?.window?.screen ?? NSScreen.main)?.visibleFrame ?? .infinite
        if placement == .leading {
            let origin = CGPoint(x: trigger.minX - offset + room - size.width, y: trigger.midY - size.height / 2)
            panel.setFrame(CGRect(origin: origin, size: size), display: true)
            return false
        }
        var origin = CGPoint(x: placement == .belowTrailing ? trigger.maxX + room - size.width : trigger.minX - room,
                             y: trigger.minY - offset + room - size.height)
        var up = false
        if placement == .above || (origin.y + room < screen.minY && trigger.maxY + offset + size.height - room <= screen.maxY) {
            origin.y = trigger.maxY + offset - room
            up = true
        }
        origin.x = min(max(origin.x, screen.minX + 4 - room), screen.maxX - size.width + room - 4)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        return up
    }

    func dismiss(animated: Bool = true) {
        guard let panel, !closing else { return }
        closing = true
        removeMonitors()
        let finish = { [weak self] in
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            self?.panel = nil
            self?.host = nil
            self?.closing = false
        }
        guard animated else { finish(); return }
        // Leaving is a quick tween, crisper than the entrance.
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.06
            panel.animator().alphaValue = 0
        }, completionHandler: { MainActor.assumeIsolated { finish() } })
    }

    private func requestDismiss() {
        dismiss()
        onDismiss?()
    }

    private func installMonitors() {
        removeMonitors()
        // A click anywhere outside the popup (and outside its trigger, which toggles it itself) closes it.
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown], handler: { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.type == .keyDown {
                // Escape closes the innermost popup: the one with the keyboard, or this one from its trigger's window.
                if event.keyCode == 53, event.window === panel || event.window === self.anchor?.window {
                    self.requestDismiss()
                    return nil
                }
                return event
            }
            // Clicks in this popup, or in a popup opened from it, are inside.
            var window = event.window
            while let current = window {
                if current === panel { return event }
                window = current.parent
            }
            if let anchor = self.anchor, event.window === anchor.window,
               anchor.bounds.contains(anchor.convert(event.locationInWindow, from: nil)) { return event }
            self.requestDismiss()
            return event
        }) { monitors.append(local) }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.requestDismiss() }
        }) { monitors.append(global) }
    }

    private func removeMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }
}

/// The surface a popup's content sits on: two levels above what it opened from, with a level-3 shadow whatever that
/// is. It enters from 96% height and 4 pt toward its trigger while fading in, on the fast spring.
struct FluidPopupSurface<Content: View>: View {
    var padding: CGFloat = 4
    var minWidth: CGFloat = 0
    var maxHeight: CGFloat = 300
    /// The surface level the trigger sits on.
    var substrate = 2
    @ViewBuilder var content: Content
    @Environment(\.fluidPopupOpensUp) private var opensUp
    @State private var shown = false

    /// Room for the shadow inside the borderless panel.
    static var shadowRoom: CGFloat { 14 }

    var body: some View {
        content
            .padding(padding)
            .frame(minWidth: minWidth, alignment: .leading)
            .frame(maxHeight: maxHeight)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.fluidSurfaceLevel, min(substrate + 2, 8))
            .fluidSurface(min(substrate + 2, 8), radius: Fluid.Radius.container, shadow: 3)
            .padding(Self.shadowRoom)
            // It grows from the edge nearest its trigger.
            .scaleEffect(x: 1, y: shown ? 1 : 0.96, anchor: opensUp ? .bottom : .top)
            .offset(y: shown ? 0 : (opensUp ? 4 : -4))
            .opacity(shown ? 1 : 0)
            .onAppear { withAnimation(Fluid.Motion.fast) { shown = true } }
    }
}
