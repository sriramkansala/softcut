import AVFoundation
import os
import AppKit
import Combine
import GlideCore
import SwiftUI

public enum EditorSelection: Equatable {
    case none
    case zoom(UUID)
    case slice(UUID)
    case mask(UUID)
}

public enum PreviewState: Equatable {
    case loading
    case ready
    case failed(String)
}

public enum ExportFormat: String, CaseIterable {
    case video, gif

    public var title: String { self == .video ? "Video (MP4)" : "Animated GIF" }
    public var fileExtension: String { self == .video ? "mp4" : "gif" }
}

public enum ExportState: Equatable {
    case idle
    case running(Double)
    case finished(URL)
    case failed(String)
}

/// Why a recording could not be added to a project.
public enum AttachError: LocalizedError {
    case sameRecording
    case alreadyAdded
    case differentShape(String, String)

    public var errorDescription: String? {
        switch self {
        case .sameRecording: return "That is the recording already open. To repeat part of it, copy a clip and paste it."
        case .alreadyAdded: return "That recording is already in this project. To repeat part of it, copy a clip and paste it."
        case .differentShape(let mine, let theirs):
            return "That recording was made on a screen of a different shape (\(theirs), this project is \(mine)), so it would not fit the video. Record it on the same display."
        }
    }
}

/// Everything about one open project: the edit being made, the live preview that follows it,
/// undo and redo, autosave and export.
///
/// Where the playhead is. It moves 30 times a second during playback, so it lives apart from `EditorModel`: if the model
/// published it, every panel in the window would be worked out again on every tick.
@MainActor
public final class PlayheadClock: ObservableObject {
    @Published public fileprivate(set) var time = 0.0
    nonisolated init() {}
}

/// The video is clips from one or more recordings, one after another. The playhead and the timeline are in
/// the video's own time. Zooms, masks and other things tied to a recording keep that recording's time, so
/// the model converts between the two where it needs to.
@MainActor
public final class EditorModel: ObservableObject {
    /// The project's own recording.
    public let bundle: RecordingBundle
    /// Plays the preview. A preview that has to be rebuilt gets a new player, so the old one can stay on screen meanwhile.
    @Published public private(set) var player = AVPlayer()

    @Published public private(set) var project: EditProject
    /// The project's recording and any attached ones, loaded.
    @Published public private(set) var sources: SourceSet
    @Published public var selection = EditorSelection.none
    /// Where the playhead is, for the few views that show it. Everything else must not observe it: see `PlayheadClock`.
    public let clock = PlayheadClock()
    /// Where the playhead is, in seconds of the video.
    public private(set) var playhead: Double {
        get { clock.time }
        set { clock.time = newValue }
    }
    @Published public private(set) var isPlaying = false
    @Published public private(set) var previewState = PreviewState.loading
    @Published public private(set) var exportState = ExportState.idle
    @Published public private(set) var undoDepth = 0
    @Published public private(set) var redoDepth = 0
    /// Clips that were cut or copied, ready to paste.
    @Published public private(set) var clipboard: [TimeSegment] = []
    @Published public var pixelsPerSecond = 60.0
    @Published public var exportCodec = ExportCodec.h264
    @Published public var exportFormat = ExportFormat.video
    @Published public var gifWidth = 720
    @Published public var gifFPS = 15
    /// Something to tell the person, such as a recording that could not be added.
    @Published public var notice: String?
    /// True while a voice-over is being recorded.
    @Published public private(set) var isRecordingVoiceOver = false
    /// True while captions are being made from the speech.
    @Published public private(set) var isTranscribing = false

    private var session: PreviewSession?
    private var motionStop: Task<Void, Never>?
    private var undoStack: [EditProject] = []
    private var redoStack: [EditProject] = []
    private var lastEditKey: String?
    private var lastEditAt = Date.distantPast
    private var previewTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var generation = 0
    /// Works out edits for the preview one at a time, away from the main thread.
    private let previewQueue = DispatchQueue(label: "app.glide.preview-edits", qos: .userInitiated)
    private let latestRefresh = OSAllocatedUnfairLock(initialState: 0)
    private var appliedRefresh = 0
    private var seekTarget: CMTime?
    private var isSeeking = false
    private var timeObserver: Any?
    private nonisolated(unsafe) var followedPlayer: AVPlayer?
    private var playerStatus: AnyCancellable?
    private var posterCache: [String: CGImage] = [:]
    @Published private var filmstrips: [String: Filmstrip] = [:]
    private var filmstripsLoading: Set<String> = []
    private let voiceRecorder = VoiceOverRecorder()
    private var voiceOverStart = 0.0

    public init(bundle: RecordingBundle) {
        self.bundle = bundle
        let project = EditProject.open(bundle)
        self.project = project
        self.sources = SourceSet.load(primary: bundle, project: project)

        follow(player)
        reportMissingRecordings()
    }

    deinit {
        if let timeObserver { followedPlayer?.removeTimeObserver(timeObserver) }
    }

    // MARK: Facts

    /// Length of the video.
    public var outputDuration: Double { project.timeMap.outputDuration }
    public var hasWebcam: Bool { sources.primary.webcamURL != nil || sources.attached.values.contains { $0.webcamURL != nil } }
    public var canUndo: Bool { undoDepth > 0 }
    public var canRedo: Bool { redoDepth > 0 }
    public var canPaste: Bool { !clipboard.isEmpty }
    public var title: String { bundle.folder.lastPathComponent }

    /// Recordings the project uses that could not be found on disk.
    public var missingRecordings: [AttachedSource] { sources.missing(in: project) }

    /// Length of a recording, in its own seconds.
    public func duration(of source: UUID?) -> Double {
        sources.bundle(source)?.manifest.duration ?? project.duration(of: source, primary: bundle.manifest.duration)
    }

    public func name(of source: UUID?) -> String {
        source == nil ? bundle.folder.lastPathComponent : (project.attachment(source)?.name ?? "Missing recording")
    }

    /// Which clip, and so which recording and moment, a moment of the video comes from.
    public func location(atOutput time: Double) -> TimeMap.Location? { project.timeMap.locate(output: time) }

    public var playheadLocation: TimeMap.Location? { location(atOutput: playhead) }

    /// Recordings in the order they first appear in the video, for coloring and naming.
    public var sourceOrder: [UUID?] {
        var order: [UUID?] = [nil]
        for clip in project.slices where !order.contains(where: { $0 == clip.sourceID }) { order.append(clip.sourceID) }
        return order
    }

    private func reportMissingRecordings() {
        let missing = missingRecordings
        if !missing.isEmpty {
            notice = "\(missing.count == 1 ? "A recording" : "\(missing.count) recordings") in this project could not be found (\(missing.map(\.name).joined(separator: ", "))). Their clips are left out of the video."
        }
    }

    // MARK: Preview

    public func loadPreview() async {
        previewState = .loading
        do {
            let fresh = try await PreviewSession.make(sources: sources, project: project)
            session = fresh
            player.replaceCurrentItem(with: fresh.item)
            previewState = .ready
            seek(toOutput: playhead)
        } catch {
            previewState = .failed(error.localizedDescription)
        }
    }

    /// Brings the preview in line with the project, in place when possible.
    private func refreshPreview() async {
        guard let session else { return }
        let project = self.project
        let latest = latestRefresh
        let mine = latest.withLock { newest in
            newest += 1
            return newest
        }
        let outcome: PreviewSession.Update?? = await withCheckedContinuation { finished in
            previewQueue.async {
                // A newer edit is waiting behind this one, so there is no need to work this one out.
                guard latest.withLock({ $0 }) == mine else {
                    finished.resume(returning: .none)
                    return
                }
                finished.resume(returning: .some(session.prepare(project: project)))
            }
        }
        guard self.session === session, let outcome else { return }
        if let update = outcome {
            guard mine > appliedRefresh else { return }
            appliedRefresh = mine
            session.apply(update, redrawing: !isPlaying)
            return
        }
        guard latest.withLock({ $0 }) == mine else { return }
        // Cuts, order, speed, the webcam or the recordings changed: the preview has to be built again.
        generation += 1
        let build = generation
        let resumeAt = playhead
        let wasPlaying = isPlaying
        player.pause()
        do {
            let fresh = try await PreviewSession.make(sources: sources, project: project)
            guard build == generation else { return }
            let next = AVPlayer(playerItem: fresh.item)
            next.isMuted = player.isMuted
            await next.seek(to: CMTime(seconds: min(resumeAt, fresh.duration), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            guard build == generation else { return }
            self.session = fresh
            switchPlayer(to: next)
            if playhead != resumeAt { seek(toOutput: playhead) }
            if wasPlaying { next.play() }
        } catch {
            previewState = .failed(error.localizedDescription)
        }
    }

    /// Keeps up with where a player is and whether it is playing.
    private func follow(_ player: AVPlayer) {
        followedPlayer = player
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.playerMoved(to: time.seconds) }
        }
        playerStatus = player.publisher(for: \.timeControlStatus)
            .receive(on: RunLoop.main)
            .sink { [weak self] status in self?.isPlaying = status != .paused }
    }

    private func switchPlayer(to next: AVPlayer) {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        player.pause()
        seekTarget = nil
        isSeeking = false
        player = next
        follow(next)
    }

    private func schedulePreviewRefresh() {
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(30))
            guard !Task.isCancelled else { return }
            await self?.refreshPreview()
        }
    }

    private func playerMoved(to outputTime: Double) {
        // While seeking the player still reports where it was, which would pull the playhead back.
        guard !isSeeking else { return }
        playhead = outputTime
        if isPlaying, outputTime >= outputDuration - 0.03 {
            player.pause()
            if isRecordingVoiceOver { stopVoiceOver() }
        }
    }

    // MARK: Transport

    public func togglePlay() {
        guard previewState == .ready else { return }
        motionStop?.cancel()
        if isRecordingVoiceOver {
            stopVoiceOver()
            return
        }
        if isPlaying {
            player.pause()
        } else {
            if player.currentTime().seconds >= outputDuration - 0.05 { seek(toOutput: 0) }
            player.play()
        }
    }

    public func seek(toOutput time: Double) {
        let clamped = min(max(0, time), outputDuration)
        playhead = clamped
        seekTarget = CMTime(seconds: clamped, preferredTimescale: 600)
        if !isSeeking { seekToTarget() }
    }

    /// One seek at a time, each to the latest place asked for. Dragging asks far faster than frames can be drawn, and
    /// a player given every request falls behind and then plays them all back.
    private func seekToTarget() {
        guard let target = seekTarget, player.currentItem != nil else {
            seekTarget = nil
            isSeeking = false
            return
        }
        seekTarget = nil
        isSeeking = true
        let seeking = player
        seeking.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.player === seeking else { return }
                self.seekToTarget()
            }
        }
    }

    /// Moves the playhead to a moment of a recording, where that moment is in the video.
    public func seek(toSource time: Double, of source: UUID? = nil) {
        seek(toOutput: project.timeMap.outputTime(forSource: time, source: source))
    }

    public func step(frames: Int) {
        player.pause()
        seek(toOutput: playhead + Double(frames) / 30)
    }

    // MARK: Captions

    /// Every caption line with where it falls in the video, in the order it plays. Lines in cut parts have no position.
    public var allCaptions: [(line: CaptionLine, outputStart: Double?)] {
        project.captions.map { line in
            let pieces = project.timeMap.pieces(source: line.source, sourceStart: line.start, sourceEnd: line.end)
            return (line, pieces.first?.outputStart)
        }
        .sorted { ($0.outputStart ?? .infinity, $0.line.start) < ($1.outputStart ?? .infinity, $1.line.start) }
    }

    /// Writes captions for what was said, using speech recognition on this Mac.
    public func generateCaptions(language: String) async {
        guard !isTranscribing else { return }
        isTranscribing = true
        defer { isTranscribing = false }
        guard await Transcriber.requestAccess() else {
            notice = Transcriber.Failure.notAllowed.errorDescription
            return
        }
        let locale = Locale(identifier: language)
        var made: [CaptionLine] = []
        var done: [UUID?] = []
        var firstError: String?
        for id in [nil] + project.attachments.map({ Optional($0.id) }) {
            guard let recording = sources.bundle(id) else { continue }
            do {
                made += try await Transcriber.transcribe(recording, source: id, locale: locale)
                done.append(id)
            } catch {
                if firstError == nil { firstError = error.localizedDescription }
            }
        }
        if done.isEmpty {
            notice = firstError ?? "No captions could be made."
            return
        }
        edit { project in
            project.captions.removeAll { line in done.contains { $0 == line.source } }
            project.captions += made
        }
        if made.isEmpty { notice = "No speech was found, so there are no captions." }
        else if let firstError { notice = "Some recordings were skipped: \(firstError)" }
    }

    public func addCaptionAtPlayhead() {
        guard let location = location(atOutput: playhead) else { return }
        let start = location.sourceTime
        let line = CaptionLine(source: location.segment.sourceID, start: start,
                               end: min(start + 2.5, location.segment.sourceEnd), text: "New caption")
        edit { $0.captions.append(line) }
    }

    public func updateCaption(_ id: UUID, key: String, _ change: @escaping (inout CaptionLine) -> Void) {
        edit(coalescing: key) { project in
            guard let index = project.captions.firstIndex(where: { $0.id == id }) else { return }
            change(&project.captions[index])
        }
    }

    public func removeCaption(_ id: UUID) { edit { $0.captions.removeAll { $0.id == id } } }

    public func removeAllCaptions() { edit { $0.captions = [] } }

    /// Saves the captions as an SRT subtitle file, timed to the finished video.
    /// Replaces the captions with the lines of an SRT or WebVTT file, whose times are the finished video's.
    public func importCaptions(from url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            notice = "\(url.lastPathComponent) could not be read."
            return
        }
        let contents = String(decoding: data, as: UTF8.self)
        let timeMap = project.timeMap
        let lines = SubtitleFile.parse(contents).compactMap { entry -> CaptionLine? in
            guard entry.start < outputDuration, let location = timeMap.locate(output: entry.start) else { return nil }
            let end = location.sourceTime + (entry.end - entry.start) * location.segment.speed
            return CaptionLine(source: location.segment.sourceID, start: location.sourceTime, end: end, text: entry.text)
        }
        guard !lines.isEmpty else {
            notice = "No captions were found in \(url.lastPathComponent)."
            return
        }
        edit {
            $0.captions = lines
            $0.settings.style.showCaptions = true
        }
    }

    public func exportSubtitles(to url: URL) {
        do {
            try SubtitleFile.srt(lines: project.captions, timeMap: project.timeMap).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            notice = "Could not save the subtitles: \(error.localizedDescription)"
        }
    }

    // MARK: Sound

    /// Uses a sound file as music under the video.
    public func chooseMusic(from url: URL) async {
        let asset = AVURLAsset(url: url)
        let hasSound = ((try? await asset.loadTracks(withMediaType: .audio))?.isEmpty == false)
        guard hasSound else {
            notice = "\(url.lastPathComponent) has no sound Softcut can read."
            return
        }
        edit { $0.audio.music = BackingMusic(path: url.path, name: url.deletingPathExtension().lastPathComponent) }
    }

    /// Uses one of the tracks that come with Glide, making its sound file first if this is the first time.
    public func chooseBuiltInMusic(_ track: BuiltInMusic.Track) async {
        guard let url = try? await Task.detached(priority: .userInitiated, operation: { try BuiltInMusic.url(for: track) }).value else {
            notice = "\(track.name) could not be made."
            return
        }
        edit { $0.audio.music = BackingMusic(path: url.path, name: track.name) }
    }

    public func removeMusic() { edit { $0.audio.music = nil } }

    public func updateMusic(key: String, _ change: @escaping (inout BackingMusic) -> Void) {
        edit(coalescing: key) { project in
            if var music = project.audio.music {
                change(&music)
                project.audio.music = music
            }
        }
    }

    /// Starts recording the microphone while the video plays from the playhead, with its own sound off so it is not recorded too.
    public func startVoiceOver() async {
        guard !isRecordingVoiceOver, previewState == .ready else { return }
        guard await VoiceOverRecorder.requestAccess() else {
            notice = "Softcut needs the microphone for a voice-over. Allow it in System Settings, Privacy & Security, Microphone."
            return
        }
        do {
            try voiceRecorder.start(in: bundle.folder.appendingPathComponent("voiceovers"))
        } catch {
            notice = "Could not start the microphone: \(error.localizedDescription)"
            return
        }
        if playhead >= outputDuration - 0.1 { seek(toOutput: 0) }
        voiceOverStart = playhead
        isRecordingVoiceOver = true
        player.isMuted = true
        player.play()
    }

    /// Stops the voice-over and puts it in the video where it began.
    public func stopVoiceOver() {
        guard isRecordingVoiceOver else { return }
        isRecordingVoiceOver = false
        player.pause()
        player.isMuted = false
        guard let result = voiceRecorder.stop(), result.duration > 0.3 else {
            notice = "Nothing was recorded."
            return
        }
        let voice = VoiceOver(path: result.url.path, start: voiceOverStart, duration: result.duration)
        edit { $0.audio.voiceOvers.append(voice) }
    }

    public func updateVoiceOver(_ id: UUID, key: String, _ change: @escaping (inout VoiceOver) -> Void) {
        edit(coalescing: key) { project in
            guard let index = project.audio.voiceOvers.firstIndex(where: { $0.id == id }) else { return }
            change(&project.audio.voiceOvers[index])
        }
    }

    public func removeVoiceOver(_ id: UUID) { edit { $0.audio.voiceOvers.removeAll { $0.id == id } } }

    // MARK: Mockups

    /// Shows the video on the screen of a 3D device, or takes it off again. Choosing a device or a motion plays the
    /// arrival from the start and stops when the device has come to rest, so the choice can be seen straight away.
    public func setMockup(_ choice: MockupChoice?) {
        edit { $0.settings.style.mockup = choice }
        guard let choice, previewState == .ready,
              let motion = MockupLibrary.shared.device(id: choice.deviceID)?.motion(id: choice.motionID) else { return }
        motionStop?.cancel()
        seek(toOutput: 0)
        player.play()
        motionStop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(motion.settle, 3) + 0.3))
            guard !Task.isCancelled else { return }
            self?.player.pause()
        }
    }

    // MARK: Editing

    /// Applies a change to the project. Repeated changes under the same `key` within a second
    /// (dragging a slider) count as one step for undo.
    public func edit(coalescing key: String? = nil, _ change: (inout EditProject) -> Void) {
        var next = project
        change(&next)
        guard next != project else { return }
        let continuing = key != nil && key == lastEditKey && Date().timeIntervalSince(lastEditAt) < 1
        if !continuing {
            undoStack.append(project)
            if undoStack.count > 200 { undoStack.removeFirst() }
            redoStack.removeAll()
        }
        lastEditKey = key
        lastEditAt = Date()
        project = next
        undoDepth = undoStack.count
        redoDepth = 0
        keepSelectionValid()
        scheduleSave()
        schedulePreviewRefresh()
    }

    public func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(project)
        project = previous
        finishHistoryStep()
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(project)
        project = next
        finishHistoryStep()
    }

    private func finishHistoryStep() {
        lastEditKey = nil
        undoDepth = undoStack.count
        redoDepth = redoStack.count
        keepSelectionValid()
        scheduleSave()
        schedulePreviewRefresh()
    }

    private func keepSelectionValid() {
        switch selection {
        case .none: break
        case .zoom(let id): if project.zoom(id) == nil { selection = .none }
        case .slice(let id): if project.slice(id) == nil { selection = .none }
        case .mask(let id): if project.mask(id) == nil { selection = .none }
        }
    }

    /// A binding to one setting. Dragging a slider through it is a single undo step.
    public func binding<T>(_ keyPath: WritableKeyPath<EditProject, T>, _ key: String) -> Binding<T> {
        Binding(get: { self.project[keyPath: keyPath] },
                set: { value in self.edit(coalescing: key) { $0[keyPath: keyPath] = value } })
    }

    /// A binding that lets a SwiftUI color well edit an RGB setting.
    public func colorBinding(_ keyPath: WritableKeyPath<EditProject, RGB>, _ key: String) -> Binding<Color> {
        Binding(get: {
                    let rgb = self.project[keyPath: keyPath]
                    return Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b)
                },
                set: { color in
                    let converted = NSColor(color).usingColorSpace(.sRGB) ?? .black
                    self.edit(coalescing: key) {
                        $0[keyPath: keyPath] = RGB(Double(converted.redComponent), Double(converted.greenComponent), Double(converted.blueComponent))
                    }
                })
    }

    // MARK: Zooms

    /// Which recording a zoom belongs to.
    public func source(ofZoom id: UUID) -> UUID? { project.locateZoom(id)?.source }

    /// Every zoom in every recording, in the order they first appear in the video. Zooms whose stretch was cut out come last.
    public var allZooms: [(zoom: ZoomSegment, source: UUID?, outputStart: Double?)] {
        var rows: [(zoom: ZoomSegment, source: UUID?, outputStart: Double?)] = []
        for source in sourceOrder {
            for zoom in project.zooms(of: source) {
                let first = project.timeMap.pieces(source: source, sourceStart: zoom.start, sourceEnd: zoom.end).first
                rows.append((zoom, source, first?.outputStart))
            }
        }
        return rows.sorted { ($0.outputStart ?? .infinity) < ($1.outputStart ?? .infinity) }
    }

    public func addZoomAtPlayhead() {
        guard let location = playheadLocation else { return }
        let source = location.segment.sourceID
        let aim = cursorPosition(source: source, atSource: location.sourceTime)
        var added: UUID?
        edit {
            added = $0.addZoom(source: source, at: location.sourceTime, recordingDuration: duration(of: source), aim: aim, scale: $0.settings.zoomScale)
        }
        if let added { selection = .zoom(added) }
    }

    /// Moves a zoom so it starts at `start` seconds of its recording.
    public func moveZoom(_ id: UUID, toStart start: Double) {
        guard let zoom = project.zoom(id) else { return }
        let source = self.source(ofZoom: id)
        edit(coalescing: "zoom-move-\(id)") { $0.moveZoom(id, by: start - zoom.start, recordingDuration: duration(of: source)) }
    }

    public func resizeZoom(_ id: UUID, start: Double? = nil, end: Double? = nil) {
        guard let zoom = project.zoom(id) else { return }
        let source = self.source(ofZoom: id)
        edit(coalescing: "zoom-resize-\(id)") {
            $0.setZoomRange(id, start: start ?? zoom.start, end: end ?? zoom.end, recordingDuration: duration(of: source))
        }
    }

    public func updateZoom(_ id: UUID, key: String, _ change: @escaping (inout ZoomSegment) -> Void) {
        edit(coalescing: "zoom-\(key)-\(id)") { $0.updateZoom(id, change) }
    }

    /// Replaces the zooms of every recording in the video with the ones Glide would choose.
    /// Sets how far every zoom goes in, and how far the next ones chosen by Glide will.
    public func setZoomAmount(_ scale: Double) {
        edit(coalescing: "zoom-amount") { project in
            project.settings.zoomScale = scale
            project.settings.typingZoomScale = scale
            for i in project.zooms.indices where project.zooms[i].presentation == .camera { project.zooms[i].scale = scale }
            for a in project.attachments.indices {
                for i in project.attachments[a].zooms.indices where project.attachments[a].zooms[i].presentation == .camera {
                    project.attachments[a].zooms[i].scale = scale
                }
            }
        }
    }

    public func regenerateZooms() {
        edit { project in
            for source in sourceOrder {
                if let recording = sources.bundle(source) { project.regenerateZooms(for: recording, source: source) }
            }
        }
        selection = .none
    }

    // MARK: Masks

    public func source(ofMask id: UUID) -> UUID? { project.locateMask(id)?.source }

    /// Every mask in every recording, in the order they first appear in the video.
    public var allMasks: [(mask: MaskRegion, source: UUID?, outputStart: Double?)] {
        var rows: [(mask: MaskRegion, source: UUID?, outputStart: Double?)] = []
        for source in sourceOrder {
            for mask in project.masks(of: source) {
                let first = project.timeMap.pieces(source: source, sourceStart: mask.start, sourceEnd: mask.end).first
                rows.append((mask, source, first?.outputStart))
            }
        }
        return rows.sorted { ($0.outputStart ?? .infinity) < ($1.outputStart ?? .infinity) }
    }

    public func addMaskAtPlayhead(rect: CropRect? = nil) {
        guard let location = playheadLocation else { return }
        let source = location.segment.sourceID
        var added: UUID?
        edit { added = $0.addMask(source: source, at: location.sourceTime, recordingDuration: duration(of: source), rect: rect) }
        if let added { selection = .mask(added) }
    }

    public func moveMask(_ id: UUID, toStart start: Double) {
        guard let mask = project.mask(id) else { return }
        let source = self.source(ofMask: id)
        edit(coalescing: "mask-move-\(id)") { $0.moveMask(id, by: start - mask.start, recordingDuration: duration(of: source)) }
    }

    public func resizeMask(_ id: UUID, start: Double? = nil, end: Double? = nil) {
        guard let mask = project.mask(id) else { return }
        let source = self.source(ofMask: id)
        edit(coalescing: "mask-resize-\(id)") {
            $0.setMaskRange(id, start: start ?? mask.start, end: end ?? mask.end, recordingDuration: duration(of: source))
        }
    }

    public func updateMask(_ id: UUID, key: String, _ change: @escaping (inout MaskRegion) -> Void) {
        edit(coalescing: "mask-\(key)-\(id)") { $0.updateMask(id, change) }
    }

    // MARK: Clips

    /// The moment of a clip's recording that is `outputTime` seconds into the video.
    public func sourceTime(inClip index: Int, atOutput outputTime: Double) -> Double {
        let segments = project.timeMap.segments
        guard segments.indices.contains(index) else { return 0 }
        let start = project.timeMap.outputStarts[index]
        let segment = segments[index]
        return segment.sourceStart + (outputTime - start) * segment.speed
    }

    public func splitAtPlayhead() {
        guard let location = playheadLocation else { return }
        edit { $0.split(clipID: location.segment.id, atSource: location.sourceTime) }
    }

    /// Trims a clip to show `start` to `end` seconds of its recording.
    public func trimSlice(_ id: UUID, start: Double? = nil, end: Double? = nil) {
        guard let slice = project.slice(id) else { return }
        edit(coalescing: "slice-trim-\(id)") {
            $0.setSliceRange(id, start: start ?? slice.sourceStart, end: end ?? slice.sourceEnd, recordingDuration: duration(of: slice.sourceID))
        }
    }

    public func setSpeed(_ id: UUID, _ speed: Double) {
        edit(coalescing: "slice-speed-\(id)") { $0.setSliceSpeed(id, speed) }
    }

    public func updateSlice(_ id: UUID, key: String, _ change: @escaping (inout TimeSegment) -> Void) {
        edit(coalescing: "slice-\(key)-\(id)") { $0.updateSlice(id, change) }
    }

    public func restoreCuts() {
        edit { $0.restoreAllSlices(recordingDuration: bundle.manifest.duration) }
        selection = .none
    }

    private var selectedSliceID: UUID? {
        if case .slice(let id) = selection { return id }
        return nil
    }

    /// Takes the selected clip out of the video and keeps it to paste. The video closes up over the gap.
    public func cutSelection() {
        guard let id = selectedSliceID, let clip = project.slice(id), project.slices.count > 1 else { return }
        clipboard = [clip]
        edit { $0.deleteSlice(id) }
        selection = .none
    }

    public func copySelection() {
        guard let id = selectedSliceID, let clip = project.slice(id) else { return }
        clipboard = [clip]
    }

    /// Pastes after the selected clip, or after the clip the playhead is on, or at the end.
    public func paste() {
        guard canPaste else { return }
        let after = selectedSliceID.flatMap { project.sliceIndex($0) } ?? playheadLocation?.index
        insertClipboard(at: (after ?? (project.slices.count - 1)) + 1)
    }

    public func pasteAtEnd() {
        guard canPaste else { return }
        insertClipboard(at: project.slices.count)
    }

    private func insertClipboard(at index: Int) {
        var inserted: [UUID] = []
        let clips = clipboard
        edit { inserted = $0.insertSlices(clips, at: index) }
        guard let first = inserted.first, let at = project.sliceIndex(first) else { return }
        selection = .slice(first)
        seek(toOutput: project.timeMap.outputStarts.indices.contains(at) ? project.timeMap.outputStarts[at] : 0)
    }

    /// Moves the selected clip earlier or later in the video.
    public func moveSelectedClip(by offset: Int) {
        guard let id = selectedSliceID, let index = project.sliceIndex(id) else { return }
        edit { $0.moveSlice(id, toIndex: index + offset) }
    }

    public var canMoveSelectedClipEarlier: Bool { selectedSliceID.flatMap { project.sliceIndex($0) }.map { $0 > 0 } ?? false }
    public var canMoveSelectedClipLater: Bool { selectedSliceID.flatMap { project.sliceIndex($0) }.map { $0 < project.slices.count - 1 } ?? false }

    public func deleteSelection() {
        switch selection {
        case .none: return
        case .zoom(let id): edit { $0.deleteZoom(id) }
        case .slice(let id): edit { $0.deleteSlice(id) }
        case .mask(let id): edit { $0.deleteMask(id) }
        }
        selection = .none
    }

    public func resetToAutomaticEdit() {
        edit { $0 = EditProject.auto(for: bundle) }
        selection = .none
    }

    // MARK: Adding recordings

    /// Recordings that could still be added: everything in `candidates` that is not already in this project.
    public func addable(_ candidates: [RecordingItem]) -> [RecordingItem] {
        let used = Set(([bundle.folder] + project.attachments.map(\.folder)).map { $0.standardizedFileURL })
        return candidates.filter { !used.contains($0.folder.standardizedFileURL) }
    }

    /// Adds another recording to the end of the video, with its own automatic zooms.
    public func attachRecording(from folder: URL) throws {
        let other = try RecordingBundle.load(from: folder)
        let here = folder.standardizedFileURL
        guard here != bundle.folder.standardizedFileURL else { throw AttachError.sameRecording }
        guard !project.attachments.contains(where: { $0.folder.standardizedFileURL == here }) else { throw AttachError.alreadyAdded }

        // It is drawn into the same canvas, so it has to be the same shape of screen.
        let mine = bundle.manifest, theirs = other.manifest
        let myShape = mine.displayWidth / mine.displayHeight
        let theirShape = theirs.displayWidth / theirs.displayHeight
        guard abs(myShape - theirShape) / myShape < 0.02 else {
            throw AttachError.differentShape("\(Int(mine.displayWidth))×\(Int(mine.displayHeight))", "\(Int(theirs.displayWidth))×\(Int(theirs.displayHeight))")
        }

        let id = UUID()
        let automatic = EditProject.auto(for: other, settings: project.settings)
        sources.add(other, as: id)
        var firstClip: UUID?
        edit { project in
            project.attach(AttachedSource(id: id, path: folder.path, name: folder.lastPathComponent, duration: theirs.duration, zooms: automatic.zooms),
                           clips: automatic.slices)
            firstClip = project.slices.first { $0.sourceID == id }?.id
        }
        if let firstClip, let index = project.sliceIndex(firstClip) {
            selection = .slice(firstClip)
            seek(toOutput: project.timeMap.outputStarts.indices.contains(index) ? project.timeMap.outputStarts[index] : 0)
        }
    }

    /// Takes out the clips whose recording cannot be found.
    public func removeMissingClips() {
        let missing = Set(missingRecordings.map(\.id))
        guard !missing.isEmpty else { return }
        edit { project in
            let kept = project.slices.filter { !missing.contains($0.sourceID ?? UUID()) }
            if !kept.isEmpty { project.slices = kept }
            project.attachments.removeAll { missing.contains($0.id) }
        }
        notice = nil
    }

    // MARK: Helpers

    /// Where the mouse was at a moment of a recording (not smoothed).
    public func cursorPosition(source: UUID?, atSource time: Double) -> SIMD2<Double> {
        guard let move = sources.bundle(source)?.input.moves.last(where: { $0.t <= time }) else { return SIMD2(0.5, 0.5) }
        return SIMD2(min(max(move.x, 0), 1), min(max(move.y, 0), 1))
    }

    /// A still of a recording's screen at a moment of it, for choosing where a zoom aims or where a mask goes.
    public func posterFrame(source: UUID?, atSource time: Double) async -> CGImage? {
        guard let recording = sources.bundle(source) else { return nil }
        let key = "\(source?.uuidString ?? "main")-\(Int((time * 2).rounded()))"
        if let cached = posterCache[key] { return cached }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: recording.videoURL))
        generator.maximumSize = CGSize(width: 1800, height: 1800)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        guard let image = try? await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image else { return nil }
        posterCache[key] = image
        return image
    }

    /// Small stills along a recording, for a clip's filmstrip on the timeline. Returns nil until they have loaded,
    /// which starts on the first request.
    public func filmstrip(for source: UUID?) -> Filmstrip? {
        let key = source?.uuidString ?? "main"
        if let strip = filmstrips[key] { return strip }
        guard !filmstripsLoading.contains(key), let recording = sources.bundle(source) else { return nil }
        filmstripsLoading.insert(key)
        let duration = max(0.1, recording.manifest.duration)
        // At most 120 stills, at least half a second apart.
        let interval = max(0.5, duration / 120)
        let count = max(1, Int(ceil(duration / interval)))
        let times = (0..<count).map { CMTime(seconds: min(duration - 0.05, (Double($0) + 0.5) * interval), preferredTimescale: 600) }
        let url = recording.videoURL
        Task { [weak self] in
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.maximumSize = CGSize(width: 220, height: 220)
            generator.requestedTimeToleranceBefore = CMTime(seconds: interval / 2, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: interval / 2, preferredTimescale: 600)
            var images = [CGImage?](repeating: nil, count: count)
            for await result in generator.images(for: times) {
                if let image = try? result.image, let index = times.firstIndex(of: result.requestedTime) { images[index] = image }
            }
            self?.filmstrips[key] = Filmstrip(interval: interval, images: images)
        }
        return nil
    }

    // MARK: Lanes

    /// True when the recordings' own sound (microphone and system audio) is muted in the video.
    public var recordedSoundMuted: Bool {
        let manifest = bundle.manifest
        guard manifest.hasMicrophone || manifest.hasSystemAudio else { return true }
        return (!manifest.hasMicrophone || project.audio.muteMicrophone) && (!manifest.hasSystemAudio || project.audio.muteSystemAudio)
    }

    public func setRecordedSoundMuted(_ muted: Bool) {
        edit { $0.audio.muteMicrophone = muted; $0.audio.muteSystemAudio = muted }
    }

    /// True when at least one zoom is switched on.
    public var anyZoomEnabled: Bool { allZooms.contains { !$0.zoom.isDisabled } }

    /// Switches every zoom, in every recording, on or off.
    public func setAllZooms(enabled: Bool) {
        edit { project in
            for i in project.zooms.indices { project.zooms[i].isDisabled = !enabled }
            for a in project.attachments.indices {
                for i in project.attachments[a].zooms.indices { project.attachments[a].zooms[i].isDisabled = !enabled }
            }
        }
    }

    /// True when at least one hidden area is switched on.
    public var anyMaskEnabled: Bool { allMasks.contains { !$0.mask.isDisabled } }

    public func setAllMasks(enabled: Bool) {
        edit { project in
            for i in project.masks.indices { project.masks[i].isDisabled = !enabled }
            for a in project.attachments.indices {
                for i in project.attachments[a].masks.indices { project.attachments[a].masks[i].isDisabled = !enabled }
            }
        }
    }

    /// A still of whatever the playhead is on.
    public func posterFrameAtPlayhead() async -> CGImage? {
        let location = playheadLocation
        return await posterFrame(source: location?.segment.sourceID, atSource: location?.sourceTime ?? 0)
    }

    /// Copies a picture into the recording folder and uses it as the background.
    public func setBackgroundImage(from url: URL) {
        let name = "background." + (url.pathExtension.isEmpty ? "png" : url.pathExtension.lowercased())
        let destination = bundle.folder.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: destination)
        guard (try? FileManager.default.copyItem(at: url, to: destination)) != nil else { return }
        edit {
            $0.settings.style.activeBackground.imageFile = name
            $0.settings.style.activeBackground.kind = .image
        }
    }

    // MARK: Saving and exporting

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Writes the edit to disk right away. Called when the window closes.
    public func saveNow() {
        saveTask?.cancel()
        try? project.save(to: bundle.folder)
    }

    public func export(to url: URL) {
        if case .running = exportState { return }
        exportState = .running(0)
        let plan = AutoEditor.makePlan(sources: sources, project: project)
        let sources = sources
        let codec = exportCodec
        let format = exportFormat
        let (gifWidth, gifFPS) = (self.gifWidth, self.gifFPS)
        Task {
            do {
                let report: @Sendable (Double) -> Void = { fraction in
                    Task { @MainActor in
                        // Each change redraws the whole editor, so only when the bar would visibly move.
                        if case .running(let shown) = self.exportState, fraction - shown < 0.005 { return }
                        self.exportState = .running(fraction)
                    }
                }
                switch format {
                case .video: try await Exporter.export(sources: sources, plan: plan, to: url, codec: codec, progress: report)
                case .gif: try await Exporter.exportGIF(sources: sources, plan: plan, to: url, width: gifWidth, fps: gifFPS, progress: report)
                }
                exportState = .finished(url)
            } catch {
                exportState = .failed(error.localizedDescription)
            }
        }
    }

    public func dismissExportResult() {
        if case .running = exportState { return }
        exportState = .idle
    }
}

/// Small stills taken at a steady interval along a recording.
public struct Filmstrip {
    public let interval: Double
    public let images: [CGImage?]

    /// The still nearest a moment of the recording.
    public func image(at time: Double) -> CGImage? {
        guard !images.isEmpty else { return nil }
        let index = min(max(Int(time / interval), 0), images.count - 1)
        return images[index] ?? images.lazy.compactMap { $0 }.first
    }
}
