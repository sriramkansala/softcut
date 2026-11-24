import AppKit
import AVFoundation
import SoftcutCore
import SwiftUI

/// Opens and keeps track of the editor and library windows.
@MainActor
public final class EditorWindows: NSObject, NSWindowDelegate {
    public static let shared = EditorWindows()

    private var editors: [URL: (window: NSWindow, model: EditorModel)] = [:]
    private var libraryWindow: NSWindow?
    /// Finished-recording windows, kept alive while they are open.
    var resultWindows: [(window: NSWindow, model: ResultModel)] = []
    /// The recordings offered by each editor's project menu. Set by the app.
    public var library: RecordingLibrary?
    /// Starts a new recording from the library window. Set by the app.
    public var startRecording: (() -> Void)?

    private func projectMenu(for window: @escaping () -> NSWindow?) -> ProjectMenu {
        ProjectMenu(projects: library?.items ?? [],
                    select: { [weak self] item in
                        guard let self, let window = window() else { return }
                        self.switchProject(in: window, to: item.folder)
                    },
                    showAll: { [weak self] in
                        guard let self, let library = self.library else { return }
                        self.showLibrary(library: library, record: self.startRecording ?? {})
                    })
    }

    /// Shows another recording in an editor window that is already open.
    private func switchProject(in window: NSWindow, to folder: URL) {
        guard let current = editors.first(where: { $0.value.window === window }) else { return }
        if current.key == folder { return }
        // Already open in its own window? Go there instead.
        if let other = editors[folder] {
            other.window.makeKeyAndOrderFront(nil)
            return
        }
        guard let bundle = try? RecordingBundle.load(from: folder) else { return }
        current.value.model.player.pause()
        current.value.model.saveNow()

        let model = EditorModel(bundle: bundle)
        editors[current.key] = nil
        editors[folder] = (window, model)
        window.contentViewController = NSHostingController(rootView: EditorView(model: model, projectMenu: projectMenu(for: { [weak window] in window })))
        window.title = "Softcut — " + folder.lastPathComponent
    }

    /// Opens the editor for a recording, or brings its window forward if it is already open.
    public func openEditor(folder: URL) throws {
        if let existing = editors[folder] {
            existing.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let bundle = try RecordingBundle.load(from: folder)
        library?.reload()
        let model = EditorModel(bundle: bundle)
        var windowRef: NSWindow?
        let view = EditorView(model: model, projectMenu: projectMenu(for: { windowRef }))
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        windowRef = window
        window.title = "Softcut — " + folder.lastPathComponent
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        // The recording's name is in the top bar as a menu, so the plain title is not shown a second time.
        window.titleVisibility = .hidden
        // An empty toolbar makes the title bar as tall as the top bar, so the window's buttons line up with its icons.
        window.toolbar = NSToolbar()
        window.toolbarStyle = .unified
        window.setContentSize(NSSize(width: 1480, height: 920))
        window.minSize = NSSize(width: 1180, height: 760)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        editors[folder] = (window, model)
    }

    /// Shows the list of recordings.
    public func showLibrary(library: RecordingLibrary, record: @escaping () -> Void) {
        library.reload()
        if let libraryWindow {
            libraryWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = LibraryView(library: library, open: { [weak self] item in
            do { try self?.openEditor(folder: item.folder) } catch {
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }, record: record)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Softcut — Recordings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        // The sidebar runs up under the title bar, beside the window's buttons.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.setContentSize(NSSize(width: 980, height: 620))
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        libraryWindow = window
    }

    public func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === libraryWindow {
            libraryWindow = nil
            return
        }
        if let key = editors.first(where: { $0.value.window === window })?.key {
            editors[key]?.model.player.pause()
            editors[key]?.model.saveNow()
            editors[key] = nil
        }
    }

    /// Saves every open edit. Called when the app quits.
    public func saveAll() {
        for editor in editors.values { editor.model.saveNow() }
    }
}

/// Draws the recordings window to an image without putting it on screen.
@MainActor
public enum LibrarySnapshot {
    public static func render(root: URL, size: CGSize) async -> NSBitmapImageRep? {
        let library = RecordingLibrary(root: root)
        let host = NSHostingView(rootView: LibraryView(library: library, open: { _ in }, record: {}).frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        // Thumbnails load in the background.
        try? await Task.sleep(for: .milliseconds(1500))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }
}

/// Draws the editor to an image without putting it on screen, so its layout can be checked.
@MainActor
public enum EditorSnapshot {
    public static func render(folder: URL, size: CGSize, tab: InspectorTab, sideTab: EditorSideTab = .media, outputTime: Double, selectZoom: Int? = nil, selectSlice: Int? = nil) async throws -> NSBitmapImageRep {
        let bundle = try RecordingBundle.load(from: folder)
        let model = EditorModel(bundle: bundle)
        if let selectZoom, model.project.zooms.indices.contains(selectZoom) {
            model.selection = .zoom(model.project.zooms[selectZoom].id)
        }
        if let selectSlice, model.project.slices.indices.contains(selectSlice) {
            model.selection = .slice(model.project.slices[selectSlice].id)
        }
        let session = try await PreviewSession.make(bundle: bundle, project: model.project, previewWidth: 1280)
        let frame = try await session.frame(atOutputTime: outputTime)
        model.seek(toOutput: outputTime)

        let host = NSHostingView(rootView: EditorView(model: model, tab: tab, sideTab: sideTab, stillImage: frame).frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        // Give SwiftUI a moment to lay out, run its tasks and load stills.
        try? await Task.sleep(for: .milliseconds(900))
        host.layoutSubtreeIfNeeded()

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw SoftcutError.writerFailed("could not draw the editor") }
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }
}
