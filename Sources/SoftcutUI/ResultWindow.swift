import AppKit
import AVFoundation
import SoftcutCore
import SwiftUI
import UniformTypeIdentifiers

/// What a finished recording looks like with Softcut's automatic edit, ready to save as a video or open in the editor.
@MainActor
public final class ResultModel: ObservableObject {
    public enum Phase: Equatable {
        case preparing
        case ready
        case saving(Double)
        case saved(URL)
        case failed(String)
    }

    public let bundle: RecordingBundle
    public let player = AVPlayer()
    @Published public private(set) var phase = Phase.preparing
    @Published public private(set) var summary = ""
    @Published public private(set) var playhead = 0.0
    @Published public private(set) var isPlaying = false
    /// A still of the video, used when drawing the window to an image (a live player cannot be captured).
    @Published var still: CGImage?

    private let project: EditProject
    private var session: PreviewSession?
    private var timeObserver: Any?

    public var duration: Double { project.timeMap.outputDuration }

    public init(bundle: RecordingBundle) {
        self.bundle = bundle
        project = EditProject.open(bundle)
        summary = Self.summary(project: project, bundle: bundle)
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.playhead = time.seconds
                self.isPlaying = self.player.timeControlStatus != .paused
            }
        }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
    }

    /// Builds the preview and starts playing it.
    public func load(autoplay: Bool = true) async {
        do {
            let session = try await PreviewSession.make(bundle: bundle, project: project, previewWidth: 1600)
            self.session = session
            player.replaceCurrentItem(with: session.item)
            phase = .ready
            if autoplay { player.play() }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    public func togglePlay() {
        if player.timeControlStatus != .paused {
            player.pause()
        } else {
            if playhead >= duration - 0.05 { seek(to: 0) }
            player.play()
        }
        isPlaying = player.timeControlStatus != .paused
    }

    public func seek(to time: Double) {
        let clamped = min(max(0, time), duration)
        playhead = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func makeStill(at time: Double) async {
        still = try? await session?.frame(atOutputTime: time)
    }

    /// Where a saved video goes unless the person picks somewhere else.
    public static var exportsFolder: URL {
        FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0].appendingPathComponent("Softcut/Exports", isDirectory: true)
    }

    public var suggestedName: String { bundle.folder.lastPathComponent + ".mp4" }

    /// Renders the video at full quality to `url`.
    public func save(to url: URL) {
        if case .saving = phase { return }
        phase = .saving(0)
        player.pause()
        let sources = SourceSet.load(primary: bundle, project: project)
        let plan = AutoEditor.makePlan(sources: sources, project: project)
        Task {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try await Exporter.export(sources: sources, plan: plan, to: url) { fraction in
                    Task { @MainActor in if case .saving = self.phase { self.phase = .saving(fraction) } }
                }
                phase = .saved(url)
            } catch {
                phase = .failed("The video could not be saved: \(error.localizedDescription)")
            }
        }
    }

    public func stop() { player.pause() }

    /// A line about what the automatic edit did, such as "1:12 · 3 zooms · typing played 3× faster".
    static func summary(project: EditProject, bundle: RecordingBundle) -> String {
        var parts: [String] = []
        let seconds = Int(project.timeMap.outputDuration)
        parts.append(String(format: "%d:%02d", seconds / 60, seconds % 60))
        let zooms = project.zooms.filter { !$0.isDisabled }.count
        parts.append(zooms == 1 ? "1 zoom" : "\(zooms) zooms")
        let fast = project.slices.filter { $0.speed > 1.01 }
        if let speed = fast.first?.speed {
            let saved = fast.reduce(0) { $0 + $1.sourceDuration - $1.outputDuration }
            parts.append(String(format: "typing played %.0f× faster (%.0fs shorter)", speed, saved))
        }
        return parts.joined(separator: " · ")
    }
}

/// The finished video, playing, with Save and Edit.
public struct ResultView: View {
    @ObservedObject var model: ResultModel
    let edit: () -> Void
    let save: () -> Void
    let close: () -> Void

    public init(model: ResultModel, edit: @escaping () -> Void, save: @escaping () -> Void, close: @escaping () -> Void) {
        self.model = model
        self.edit = edit
        self.save = save
        self.close = close
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(spacing: 10) {
            VStack(spacing: 12) {
                ZStack {
                    switch model.phase {
                    case .preparing:
                        VStack(spacing: 6) {
                            FluidThinkingIndicator(words: ["Finding your clicks", "Planning the zooms", "Smoothing the cursor", "Putting it together"])
                            Text("Your video is being edited automatically").font(Fluid.font(.caption)).foregroundStyle(Fluid.mutedForeground)
                        }
                    case .failed(let message) where model.player.currentItem == nil:
                        FluidBanner(status: .error, title: "The video could not be prepared", message: message, highContrast: true)
                            .frame(maxWidth: 440)
                    default:
                        Group {
                            if let still = model.still {
                                Image(decorative: still, scale: 1).resizable().aspectRatio(contentMode: .fit)
                            } else {
                                PlayerSurface(player: model.player)
                                    .contentShape(Rectangle())
                                    .onTapGesture { model.togglePlay() }
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                transport
            }
            .padding(14)
            .background(Theme.panel, in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.07), lineWidth: 1))

            bottomBar
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(Theme.panel, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
        }
        .padding(.horizontal, 10)
        .padding(.top, 38)
        .padding(.bottom, 10)
        .background(Theme.canvas)
        .environment(\.fluidSurfaceLevel, 2)
        .ignoresSafeArea(.container, edges: .top)
        .task { await model.load() }
    }

    /// The round play button, where the video is, and a bar to move through it.
    private var transport: some View {
        HStack(spacing: 12) {
            RoundPlayButton(isPlaying: model.isPlaying, size: 42) { model.togglePlay() }
                .disabled(model.phase == .preparing)
            Text(timecode(model.playhead, tenths: false)).font(Fluid.font(.body, monospacedDigits: true)).foregroundStyle(Fluid.foreground)
            FluidTrackSlider(value: Binding(get: { model.playhead }, set: { model.seek(to: $0) }), range: 0...max(0.1, model.duration),
                             format: { timecode($0, tenths: false) })
                .disabled(model.phase == .preparing)
            Text(timecode(model.duration, tenths: false)).font(Fluid.font(.body, monospacedDigits: true)).foregroundStyle(Fluid.mutedForeground)
        }
    }

    @ViewBuilder private var bottomBar: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Fluid.font(.title, .semibold, density: .regular)).foregroundStyle(Fluid.foreground)
                switch model.phase {
                case .saved(let url):
                    FluidInputCopy(value: url.path(percentEncoded: false)).frame(maxWidth: 460, alignment: .leading)
                case .failed(let message):
                    Text(message).font(Fluid.font(.body)).foregroundStyle(Fluid.destructive).lineLimit(2)
                case .saving(let fraction):
                    HStack(spacing: 10) {
                        FluidProgressBar(fraction: fraction).frame(width: 220)
                        Text("\(Int(fraction * 100))%").font(Fluid.font(.body, monospacedDigits: true)).foregroundStyle(Fluid.mutedForeground)
                    }
                    .padding(.top, 4)
                default:
                    Text(detail).font(Fluid.font(.body)).foregroundStyle(Fluid.mutedForeground).lineLimit(1)
                }
            }
            Spacer()
            switch model.phase {
            case .saving:
                EmptyView()
            case .saved(let url):
                FluidButton("Show in Finder", icon: "folder", variant: .tertiary, size: .regular) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                FluidButton("Edit", icon: "slider.horizontal.3", variant: .secondary, size: .regular, action: edit)
                FluidButton("Done", variant: .accent, size: .regular, action: close).keyboardShortcut(.defaultAction)
            default:
                FluidButton("Edit", icon: "slider.horizontal.3", variant: .raised, size: .regular, action: edit)
                    .fluidTooltip("Change zooms, cuts, look and sound")
                FluidButton("Save video", icon: "square.and.arrow.down", variant: .accent, size: .regular, action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.phase != .ready)
            }
        }
    }

    private var title: String {
        switch model.phase {
        case .saving: return "Saving your video…"
        case .saved: return "Saved"
        case .failed: return "Something went wrong"
        default: return "Your video is ready"
        }
    }

    private var detail: String {
        switch model.phase {
        case .saved(let url): return url.path(percentEncoded: false)
        case .failed(let message): return message
        default: return model.summary + " · zooms, cursor and look applied automatically"
        }
    }
}

extension EditorWindows {
    /// Shows a finished recording with its automatic edit, playing, with Save and Edit.
    public func showResult(folder: URL) throws {
        let bundle = try RecordingBundle.load(from: folder)
        let model = ResultModel(bundle: bundle)
        var windowRef: NSWindow?
        let view = ResultView(
            model: model,
            edit: { [weak self] in
                model.stop()
                windowRef?.close()
                do { try self?.openEditor(folder: folder) } catch { NSAlert(error: error).runModal() }
            },
            save: {
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.mpeg4Movie]
                panel.nameFieldStringValue = model.suggestedName
                try? FileManager.default.createDirectory(at: ResultModel.exportsFolder, withIntermediateDirectories: true)
                panel.directoryURL = ResultModel.exportsFolder
                if panel.runModal() == .OK, let url = panel.url { model.save(to: url) }
            },
            close: { model.stop(); windowRef?.close() })
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        windowRef = window
        window.title = "Softcut — " + folder.lastPathComponent
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.setContentSize(NSSize(width: 1120, height: 780))
        window.minSize = NSSize(width: 720, height: 520)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()
        resultWindows.append((window, model))
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                model.stop()
                self?.resultWindows.removeAll { $0.window === window }
            }
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Draws the result window to an image without putting it on screen, so its layout can be checked.
public enum ResultSnapshot {
    @MainActor
    public static func render(folder: URL, size: CGSize) async throws -> NSBitmapImageRep {
        let model = ResultModel(bundle: try RecordingBundle.load(from: folder))
        let host = NSHostingView(rootView: ResultView(model: model, edit: {}, save: {}, close: {}).frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        await model.load(autoplay: false)
        await model.makeStill(at: min(4, model.duration / 2))
        model.seek(to: min(4, model.duration / 2))
        try? await Task.sleep(for: .milliseconds(800))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw SoftcutError.writerFailed("could not draw the window") }
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }
}
