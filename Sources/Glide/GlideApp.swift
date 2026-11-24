import GlideUI
import SwiftUI

/// Opens the recording bar when Glide starts, and again when its Dock icon is clicked.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            let model = AppModel.shared
            if !model.opensEditorDirectly { model.showBar() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { AppModel.shared.showBar() }
        return true
    }
}

@main
struct GlideApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuPanelView(model: model)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: model.menuIcon)
                if !model.menuTitle.isEmpty { Text(model.menuTitle).monospacedDigit() }
            }
        }
        .menuBarExtraStyle(.window)
    }
}

extension AppModel: MenuPanelControlling {
    var menuNotes: [MenuPanelNote] {
        typingPermissionNotes.map { note in
            MenuPanelNote(id: note.pane, text: note.text) { [weak self] in self?.openPrivacySettings(note.pane) }
        }
    }

    func toggleRecording() { toggle() }
}
