import AppKit
import SwiftUI

/// A note in the menu-bar panel that can be acted on, such as a missing permission.
public struct MenuPanelNote: Identifiable {
    public let id: String
    public let text: String
    public let action: () -> Void

    public init(id: String, text: String, action: @escaping () -> Void) {
        self.id = id
        self.text = text
        self.action = action
    }
}

/// What the menu-bar panel needs from the app.
@MainActor
public protocol MenuPanelControlling: ObservableObject {
    var isRecording: Bool { get }
    var isBusy: Bool { get }
    var menuTitle: String { get }
    var microphone: Bool { get set }
    var systemAudio: Bool { get set }
    var webcam: Bool { get set }
    var autoZoom: Bool { get set }
    var zoomOnTyping: Bool { get set }
    var errorMessage: String? { get set }
    var menuNotes: [MenuPanelNote] { get }

    func toggleRecording()
    func showBar()
    func editLatest()
    func openLibrary()
    func openFolder()
}

/// Glide's menu-bar panel, built from Fluid Functionalism parts: a record button, switches for what to capture, a
/// list of places to go, and banners for anything that needs attention.
public struct MenuPanelView<Model: MenuPanelControlling>: View {
    @ObservedObject var model: Model

    public init(model: Model) { self.model = model }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button { model.toggleRecording() } label: {
                    HStack(spacing: 6) {
                        if model.isRecording {
                            RoundedRectangle(cornerRadius: 2).fill(Color(fluidHex: 0xEF4444)).frame(width: 9, height: 9)
                        } else {
                            Circle().fill(Color(fluidHex: 0xEF4444)).frame(width: 9, height: 9)
                        }
                        Text(model.isRecording ? "Stop recording" : "Start recording")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(FluidButtonStyle(variant: .primary, size: .regular, leadingIcon: true))
                .disabled(model.isBusy)
                FluidIconButton(systemName: "rectangle.on.rectangle", variant: .secondary, size: .icon, help: "Show the recording bar") {
                    model.showBar()
                }
            }
            HStack {
                Text(model.isRecording ? "Recording \(model.menuTitle)" : "Start or stop anywhere")
                Spacer()
                FluidShortcutCaps(keys: "⌃⌥R", density: .compact)
            }
            .font(Fluid.font(.caption))
            .foregroundStyle(Fluid.mutedForeground)

            Rectangle().fill(Fluid.divider).frame(height: 1)

            VStack(alignment: .leading, spacing: 0) {
                Text("Record").font(Fluid.font(.caption, .semibold)).foregroundStyle(Fluid.mutedForeground).padding(.bottom, 4)
                FluidSwitch(title: "Microphone", isOn: $model.microphone)
                FluidSwitch(title: "System audio", isOn: $model.systemAudio)
                FluidSwitch(title: "Webcam", isOn: $model.webcam)
                FluidSwitch(title: "Zoom on clicks", isOn: $model.autoZoom)
                FluidSwitch(title: "Zoom on typing", isOn: $model.zoomOnTyping)
            }
            .disabled(model.isRecording || model.isBusy)

            ForEach(model.menuNotes) { note in
                FluidBanner(status: .warning, title: note.text) {
                    FluidButton("Open", variant: .secondary, action: note.action)
                }
            }

            if let message = model.errorMessage {
                FluidBanner(status: .error, title: message, highContrast: true, onDismiss: { model.errorMessage = nil })
            }

            Rectangle().fill(Fluid.divider).frame(height: 1)

            FluidMenuList(rows: [
                .item("Edit last recording", icon: "slider.horizontal.3") { model.editLatest() },
                .item("Recordings…", icon: "film.stack") { model.openLibrary() },
                .item("Open recordings folder", icon: "folder") { model.openFolder() },
                .separator(),
                .item("Quit Softcut", icon: "power") { NSApplication.shared.terminate(nil) },
            ], reserveCheckSlot: false)
            .padding(.horizontal, -6)
        }
        .padding(12)
        .frame(width: 280)
        .background(Fluid.surface3)
        .environment(\.fluidSurfaceLevel, 3)
        .environment(\.colorScheme, .dark)
        .background {
            Button("") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q").opacity(0).frame(width: 0, height: 0)
        }
    }
}
