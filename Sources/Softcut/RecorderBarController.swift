import AppKit
import Combine
import SoftcutUI
import SwiftUI

/// The floating recording bar: a panel that stays above other windows on every desktop, never takes focus
/// from the app being recorded when it is clicked, and is never part of the video (the recorder leaves out
/// all of Softcut's own windows).
@MainActor
final class RecorderBarController: NSObject {
    private final class BarPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    private let model: AppModel
    private var panel: BarPanel?
    private var host: NSHostingView<RecorderBarView<AppModel>>?
    private var cancellables = Set<AnyCancellable>()

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    /// The display the bar is on, which is the one a display recording captures.
    var displayID: CGDirectDisplayID {
        let screen = panel?.screen ?? NSScreen.main ?? NSScreen.screens.first
        return (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? CGMainDisplayID()
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if !panel.isVisible { place(panel) }
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func hide() { panel?.orderOut(nil) }

    private func makePanel() -> BarPanel {
        let host = NSHostingView(rootView: RecorderBarView(model: model))
        host.sizingOptions = [.intrinsicContentSize]
        self.host = host

        let panel = BarPanel(contentRect: CGRect(origin: .zero, size: host.fittingSize),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = host
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The bar draws its own shadow, so the window's does not lag behind when it changes size.
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.title = "Softcut recording bar"

        // The bar changes size between choosing, counting down and recording; keep it where it is, centered on itself.
        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.resize() } }
            .store(in: &cancellables)
        return panel
    }

    private func resize() {
        guard let panel, let host, panel.isVisible else { return }
        let size = host.fittingSize
        guard abs(size.width - panel.frame.width) > 0.5 || abs(size.height - panel.frame.height) > 0.5 else { return }
        var frame = panel.frame
        frame.origin.x = frame.midX - size.width / 2
        frame.size = size
        panel.setFrame(frame, display: true, animate: false)
    }

    /// Bottom center of the screen with the mouse, above the Dock.
    private func place(_ panel: BarPanel) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        let size = host?.fittingSize ?? panel.frame.size
        let visible = screen.visibleFrame
        panel.setFrame(CGRect(x: visible.midX - size.width / 2, y: visible.minY + 16, width: size.width, height: size.height), display: true)
    }
}
