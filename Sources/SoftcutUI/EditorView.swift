import AppKit
import SoftcutCore
import SwiftUI

/// What the project menu above the video offers: the recordings, and what to do when one is picked.
public struct ProjectMenu {
    public var projects: [RecordingItem]
    public var select: (RecordingItem) -> Void
    public var showAll: () -> Void

    public init(projects: [RecordingItem], select: @escaping (RecordingItem) -> Void, showAll: @escaping () -> Void) {
        self.projects = projects
        self.select = select
        self.showAll = showAll
    }
}

/// The editor, in four blocks: the side panel on the left with the window's buttons in its top corner, the video in the
/// middle under its switcher and Export, the settings on the right, and the timeline underneath.
public struct EditorView: View {
    @ObservedObject var model: EditorModel
    @State private var tab: InspectorTab
    /// A fixed picture to show instead of the live player (used to render the editor to an image).
    private let stillImage: CGImage?
    private let projectMenu: ProjectMenu?

    public init(model: EditorModel, tab: InspectorTab = .background, sideTab: EditorSideTab = .media, stillImage: CGImage? = nil, projectMenu: ProjectMenu? = nil) {
        self.model = model
        self.stillImage = stillImage
        self.projectMenu = projectMenu
        _tab = State(initialValue: tab)
        _sideTab = State(initialValue: sideTab)
        _chat = StateObject(wrappedValue: EditorChat(model: model))
    }

    @State private var commandsOpen = false
    @State private var sideTab: EditorSideTab
    @StateObject private var chat: EditorChat
    @AppStorage("editorMediaPanelOpen") private var mediaOpen = true

    public var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                if mediaOpen {
                    SidePanel(model: model, chat: chat, projectMenu: projectMenu, tab: $sideTab, hide: toggleSidePanel)
                        .frame(width: 272)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                VStack(spacing: 8) {
                    VideoBar(model: model, projectMenu: projectMenu, showSidePanel: mediaOpen ? nil : toggleSidePanel,
                             showExport: { tab = .export }, showShortcuts: { commandsOpen = true })
                    NoticeBar(model: model)
                    PreviewArea(model: model, stillImage: stillImage, tab: tab)
                }
                InspectorView(model: model, tab: $tab)
            }
            TimelineView(model: model, projectMenu: projectMenu)
                .frame(height: TimelineView.height)
        }
        .padding(8)
        .background(Theme.canvas)
        .background(EditorKeyboardFocus())
        .preferredColorScheme(.dark)
        // The blocks run up into the title bar, with the window's buttons in the side panel's corner.
        .ignoresSafeArea(.container, edges: .top)
        .fluidDialogShell(isPresented: $commandsOpen, size: .large, alignTop: true) {
            FluidCommandMenu(commands: commands, placeholder: "Search shortcuts…") { commandsOpen = false }
        }
        .background {
            Button("") { commandsOpen.toggle() }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .task {
            if stillImage == nil { await model.loadPreview() }
        }
        .onAppear { chat.showExport = { tab = .export } }
    }

    /// Everything the command menu (⌘K) can do.
    private var commands: [FluidCommand] {
        var list: [FluidCommand] = [
            FluidCommand(id: "play", title: model.isPlaying ? "Pause" : "Play", icon: model.isPlaying ? "pause.fill" : "play.fill",
                         section: "Playback", shortcut: "Space") { model.togglePlay() },
            FluidCommand(id: "start", title: "Go to the start", icon: "backward.end", section: "Playback") { model.seek(toOutput: 0) },
            FluidCommand(id: "split", title: "Split at playhead", icon: "scissors", section: "Edit", shortcut: "S") { model.splitAtPlayhead() },
            FluidCommand(id: "zoom", title: "Add zoom at playhead", icon: "plus.magnifyingglass", section: "Edit", shortcut: "Z") { model.addZoomAtPlayhead() },
            FluidCommand(id: "blur", title: "Hide something at the playhead", detail: "Blur", icon: "eye.slash", section: "Edit", shortcut: "B",
                         keywords: ["mask", "pixelate"]) { model.addMaskAtPlayhead() },
            FluidCommand(id: "caption", title: "Add a caption line here", icon: "captions.bubble", section: "Edit") { model.addCaptionAtPlayhead() },
            FluidCommand(id: "redo-zooms", title: "Redo zooms from clicks and typing", icon: "wand.and.stars", section: "Edit",
                         keywords: ["automatic", "regenerate"]) { model.regenerateZooms() },
            FluidCommand(id: "restore", title: "Restore everything that was cut", icon: "arrow.uturn.backward", section: "Edit") { model.restoreCuts() },
            FluidCommand(id: "undo", title: "Undo", icon: "arrow.uturn.backward", section: "Edit", shortcut: "⌘Z", isEnabled: model.canUndo) { model.undo() },
            FluidCommand(id: "redo", title: "Redo", icon: "arrow.uturn.forward", section: "Edit", shortcut: "⇧⌘Z", isEnabled: model.canRedo) { model.redo() },
        ]
        list += InspectorTab.allCases.map { pane in
            FluidCommand(id: "pane-\(pane.rawValue)", title: "Show \(pane.title)", icon: pane.icon, section: "Settings",
                         keywords: ["settings", "pane", "inspector"]) { tab = pane }
        }
        list.append(FluidCommand(id: "mockups", title: "Put the video in a device", icon: "laptopcomputer", section: "Video",
                                 keywords: ["mockup", "macbook", "iphone", "3d"]) { showSide(.mockups) })
        if model.project.settings.style.mockup != nil {
            list.append(FluidCommand(id: "no-mockup", title: "Take the video out of the device", icon: "xmark", section: "Video",
                                     keywords: ["mockup", "remove"]) { model.setMockup(nil) })
        }
        list.append(FluidCommand(id: "chat", title: "Open the chat", icon: "bubble.left", section: "Video") { showSide(.chat) })
        list.append(FluidCommand(id: "export", title: "Export…", icon: "square.and.arrow.up", section: "Video") { tab = .export })
        list.append(FluidCommand(id: "finder", title: "Show recording in Finder", icon: "folder", section: "Video") {
            NSWorkspace.shared.activateFileViewerSelecting([model.bundle.folder])
        })
        return list
    }

    private func toggleSidePanel() {
        withAnimation(mediaOpen ? Fluid.Motion.slowExit : Fluid.Motion.moderate) { mediaOpen.toggle() }
    }

    private func showSide(_ side: EditorSideTab) {
        sideTab = side
        if !mediaOpen { withAnimation(Fluid.Motion.slow) { mediaOpen = true } }
    }
}

/// Text fields hold the keyboard only while they are being used, so that Space, S, Z and B reach the editor. AppKit
/// hands the first field the keyboard when a window opens, and a field keeps it after a click elsewhere; this undoes both.
private struct EditorKeyboardFocus: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Watcher() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class Watcher: NSView {
        private var monitor: Any?

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DispatchQueue.main.async { [weak window] in window?.makeFirstResponder(nil) }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak window] event in
                guard let window, event.window === window, let editor = window.firstResponder as? NSTextView else { return event }
                let holder = (editor.isFieldEditor ? editor.delegate as? NSView : nil) ?? editor
                if !holder.bounds.contains(holder.convert(event.locationInWindow, from: nil)) {
                    window.makeFirstResponder(nil)
                }
                return event
            }
        }
    }
}

/// Above the video: the switcher between recordings, with the rest of the video's actions beside it.
private struct VideoBar: View {
    @ObservedObject var model: EditorModel
    let projectMenu: ProjectMenu?
    /// Set while the side panel is hidden, which also leaves the window's buttons sitting up here.
    let showSidePanel: (() -> Void)?
    let showExport: () -> Void
    let showShortcuts: () -> Void
    @State private var confirmingReset = false

    var body: some View {
        HStack(spacing: 8) {
            if let showSidePanel {
                FluidIconButton(systemName: "sidebar.left", help: "Show the side panel", action: showSidePanel)
                    // Past the window's close, minimize and zoom buttons.
                    .padding(.leading, 72)
            }
            projectPill
            Spacer(minLength: 8)
            FluidDropdown(rows: {
                [.item("Shortcuts", icon: "command") { showShortcuts() },
                 .item("Back to the automatic edit…", icon: "wand.and.stars") { confirmingReset = true },
                 .item("Show recording in Finder", icon: "folder") { NSWorkspace.shared.activateFileViewerSelecting([model.bundle.folder]) }]
            }, width: 260, placement: .belowTrailing) { open in
                Image(systemName: "ellipsis")
                    .font(.system(size: 13))
                    .frame(width: 32, height: 32)
                    .modifier(GhostIcon(isOpen: open))
            }
            FluidButton("Export", icon: "square.and.arrow.up", variant: .accent) { showExport() }
        }
        // Centred on the same line as the window's buttons.
        .frame(height: 36)
        .environment(\.fluidSurfaceLevel, 1)
        .fluidDialog(isPresented: $confirmingReset, title: "Go back to the automatic edit?",
                     description: "Your zooms, cuts and look are replaced with what Softcut chose by itself. You can undo this.") {
            EmptyView()
        } footer: {
            FluidButton("Cancel", variant: .ghost) { confirmingReset = false }
            FluidButton("Replace my edits", variant: .primary) {
                confirmingReset = false
                model.resetToAutomaticEdit()
            }
        }
    }

    /// The project's name and length in a pill, as a menu for switching to another recording.
    private var projectPill: some View {
        FluidDropdown(rows: {
            var rows: [FluidMenuRow] = []
            if let projectMenu {
                rows.append(.label("Recordings"))
                rows += projectMenu.projects.prefix(20).map { item in
                    .item(item.name, checked: item.folder == model.bundle.folder, id: AnyHashable(item.folder)) { projectMenu.select(item) }
                }
                rows.append(.separator())
                rows.append(.item("All recordings…", icon: "film.stack") { projectMenu.showAll() })
            }
            return rows
        }, width: 300) { open in
            ProjectPill(title: model.title, detail: detail, isOpen: open)
        }
        .fluidTooltip("Switch to another recording", side: .bottom)
    }

    private var detail: String {
        let count = model.project.attachments.count
        return "\(timecode(model.outputDuration, tenths: false)) video" + (count > 0 ? " · \(count + 1) recordings" : "")
    }
}

/// The project pill: the name in full ink, its length muted after a slash, and a chevron for the list.
private struct ProjectPill: View {
    let title: String
    let detail: String
    let isOpen: Bool
    @State private var hovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                Text(title).foregroundStyle(Fluid.foreground).fontWeight(.semibold)
                Text(" / \(detail)").foregroundStyle(Fluid.mutedForeground)
            }
            .font(Fluid.font(.subtitle, density: .compact))
            .lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                .foregroundStyle(hovered || isOpen ? Fluid.foreground : Fluid.mutedForeground)
                .rotationEffect(.degrees(isOpen ? 180 : 0))
                .animation(Fluid.Motion.moderate, value: isOpen)
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(isOpen ? Fluid.surface3 : (hovered ? Fluid.surface3 : Fluid.surface2), in: shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
        .contentShape(shape)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.08), value: hovered)
    }
}

/// Ghost-button colors for a custom icon trigger.
private struct GhostIcon: ViewModifier {
    let isOpen: Bool
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .foregroundStyle(hovered || isOpen ? Fluid.foreground : Fluid.mutedForeground)
            .background(isOpen ? Fluid.active : (hovered ? Fluid.hover : .clear), in: RoundedRectangle(cornerRadius: Fluid.Radius.item, style: .continuous))
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.08), value: hovered)
    }
}

/// A message above the editor: a recording that could not be added or found, with what can be done about it.
private struct NoticeBar: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        if let notice = model.notice {
            FluidBanner(status: .warning, title: notice, highContrast: true, onDismiss: { model.notice = nil }) {
                if !model.missingRecordings.isEmpty {
                    FluidButton("Remove those clips", variant: .secondary) { model.removeMissingClips() }
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)).animation(Fluid.Motion.moderate))
        }
    }
}
