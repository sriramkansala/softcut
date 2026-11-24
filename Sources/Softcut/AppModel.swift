import AppKit
import AVFoundation
import Carbon.HIToolbox
import SoftcutCore
import SoftcutUI

@MainActor
final class AppModel: ObservableObject, RecorderBarControlling {
    static let shared = AppModel()

    enum Phase: Equatable {
        case idle
        /// Someone is picking a window or drawing an area.
        case choosing
        /// Counting down to the start.
        case countdown(Int)
        case starting
        case recording(since: Date)
        /// Writing the recording to disk after it stopped, just before the editor opens.
        case saving
    }

    @Published private(set) var phase = Phase.idle
    @Published private(set) var elapsed = 0
    @Published var errorMessage: String?

    @Published var microphone = UserDefaults.standard.bool(forKey: "microphone") {
        didSet { UserDefaults.standard.set(microphone, forKey: "microphone") }
    }
    @Published var systemAudio = UserDefaults.standard.bool(forKey: "systemAudio") {
        didSet { UserDefaults.standard.set(systemAudio, forKey: "systemAudio") }
    }
    @Published var autoZoom = UserDefaults.standard.object(forKey: "autoZoom") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoZoom, forKey: "autoZoom") }
    }
    @Published var webcam = UserDefaults.standard.bool(forKey: "webcam") {
        didSet { UserDefaults.standard.set(webcam, forKey: "webcam") }
    }
    @Published var zoomOnTyping = UserDefaults.standard.bool(forKey: "zoomOnTyping") {
        didSet { UserDefaults.standard.set(zoomOnTyping, forKey: "zoomOnTyping") }
    }
    /// What the recording bar records: the display, one window, or an area.
    @Published var mode = RecordMode(rawValue: UserDefaults.standard.string(forKey: "recordMode") ?? "") ?? .display {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "recordMode") }
    }
    @Published private(set) var cameras: [InputDevice] = []
    @Published private(set) var microphones: [InputDevice] = []
    /// The camera and microphone last chosen. Whether they are used is `webcam` and `microphone`.
    private var chosenCamera = UserDefaults.standard.string(forKey: "cameraDevice")
    private var chosenMicrophone = UserDefaults.standard.string(forKey: "microphoneDevice")

    private var session: RecordingSession?
    private var timer: Timer?
    private var hotKey: GlobalHotKey?
    private var countdownCancelled = false
    /// What the recording in progress was pointed at, so the editor can open showing the same part of the screen.
    private var currentTarget: CaptureTarget?
    private lazy var bar = RecorderBarController(model: self)

    let library = RecordingLibrary(root: AppModel.folder.appendingPathComponent("Recordings", isDirectory: true))

    static let folder = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Softcut", isDirectory: true)

    init() {
        // A regular app, with a Dock icon and menu bar, now that it has windows to edit in.
        NSApplication.shared.setActivationPolicy(.regular)
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { EditorWindows.shared.saveAll() }
        }
        // `Softcut --edit FOLDER` opens a recording straight away, which is handy for trying the editor.
        if let flag = CommandLine.arguments.firstIndex(of: "--edit"), flag + 1 < CommandLine.arguments.count {
            let folder = URL(fileURLWithPath: CommandLine.arguments[flag + 1])
            DispatchQueue.main.async { try? EditorWindows.shared.openEditor(folder: folder) }
        }
        // Control + Option + R starts and stops a recording.
        hotKey = GlobalHotKey(keyCode: kVK_ANSI_R, modifiers: controlKey | optionKey) { [weak self] in
            Task { @MainActor in self?.toggle(viaHotKey: true) }
        }
        refreshDevices()
    }

    /// Opening Softcut on a recording (`--edit`) goes straight to the editor; otherwise it opens ready to record.
    var opensEditorDirectly: Bool { CommandLine.arguments.contains("--edit") }

    var isRecording: Bool { if case .recording = phase { return true } else { return false } }
    var isBusy: Bool { phase != .idle && !isRecording }

    var menuTitle: String {
        switch phase {
        case .idle, .choosing, .countdown, .starting: return ""
        case .recording: return String(format: "%d:%02d", elapsed / 60, elapsed % 60)
        case .saving: return "Saving"
        }
    }

    var menuIcon: String {
        switch phase {
        case .idle, .choosing, .countdown, .starting: return "record.circle"
        case .recording: return "stop.circle.fill"
        case .saving: return "hourglass"
        }
    }

    func toggle(viaHotKey: Bool = false) {
        switch phase {
        case .idle: record()
        case .recording: Task { await stop(viaHotKey: viaHotKey) }
        case .countdown: cancelCountdown()
        case .choosing, .starting, .saving: break
        }
    }

    // MARK: Recording bar

    var barPhase: RecorderBarPhase {
        switch phase {
        case .idle: return .idle
        case .choosing: return .choosing
        case .countdown(let number): return .countdown(number)
        // The first moments of a recording look like it has begun.
        case .starting: return .recording(seconds: 0)
        case .recording: return .recording(seconds: elapsed)
        case .saving: return .saving
        }
    }

    /// The camera in use: the one last chosen if it is still connected, otherwise the first.
    var cameraID: String? {
        get { DeviceChoice(enabled: webcam, chosen: chosenCamera).resolved(in: cameras) }
        set {
            var choice = DeviceChoice(enabled: webcam, chosen: chosenCamera)
            choice.select(newValue)
            chosenCamera = choice.chosen
            UserDefaults.standard.set(choice.chosen, forKey: "cameraDevice")
            webcam = choice.enabled
        }
    }

    var microphoneID: String? {
        get { DeviceChoice(enabled: microphone, chosen: chosenMicrophone).resolved(in: microphones) }
        set {
            var choice = DeviceChoice(enabled: microphone, chosen: chosenMicrophone)
            choice.select(newValue)
            chosenMicrophone = choice.chosen
            UserDefaults.standard.set(choice.chosen, forKey: "microphoneDevice")
            microphone = choice.enabled
        }
    }

    func refreshDevices() {
        cameras = CaptureDevices.cameras()
        microphones = CaptureDevices.microphones()
    }

    func showBar() {
        guard phase == .idle || isRecording || phase == .saving else { return }
        refreshDevices()
        bar.show()
    }

    func closeBar() { bar.hide() }
    func quit() { NSApplication.shared.terminate(nil) }

    func record() {
        guard phase == .idle else { return }
        Task { await beginRecording() }
    }

    func stop() { Task { await stop(viaHotKey: false) } }

    func cancelCountdown() { countdownCancelled = true }

    // MARK: Recording

    /// Everything before the first frame: permissions, then what to record, then a short countdown.
    private func beginRecording() async {
        guard RecordingSession.hasScreenRecordingPermission() else {
            RecordingSession.requestScreenRecordingPermission()
            showPermissionHelp()
            return
        }
        guard await prepareDevices() else { return }
        guard let target = await chooseTarget() else { return }
        guard await countDown() else { return }
        await start(target: target)
    }

    /// Asks for the microphone and camera now, so a system prompt does not appear while counting down.
    private func prepareDevices() async -> Bool {
        if microphone, await !AVCaptureDevice.requestAccess(for: .audio) {
            microphone = false
            errorMessage = "Microphone access is off for Softcut. Turn it on in System Settings > Privacy & Security > Microphone."
            return false
        }
        if webcam, await !CameraAccess.request() {
            webcam = false
            errorMessage = "Camera access is off for Softcut. Turn it on in System Settings > Privacy & Security > Camera."
            return false
        }
        await prepareTypingAccess()
        return true
    }

    /// The display, or the window or area the person picks. Nil if they backed out.
    private func chooseTarget() async -> CaptureTarget? {
        switch mode {
        case .display:
            return CaptureTarget(displayID: bar.isVisible ? bar.displayID : CGMainDisplayID())
        case .window, .area:
            phase = .choosing
            bar.hide()
            defer { phase = .idle }
            let target: CaptureTarget?
            if mode == .window {
                target = await SelectionOverlay.pickWindow().map(CaptureTarget.window)
            } else {
                target = await SelectionOverlay.drawArea().map(CaptureTarget.area)
            }
            if target == nil { bar.show() }
            return target
        }
    }

    /// Three seconds to get ready. False if cancelled.
    private func countDown() async -> Bool {
        countdownCancelled = false
        bar.show()
        for number in (1...3).reversed() {
            phase = .countdown(number)
            try? await Task.sleep(for: .seconds(1))
            if countdownCancelled {
                phase = .idle
                return false
            }
        }
        return true
    }

    private func start(target: CaptureTarget) async {
        phase = .starting
        // A beat for the bar to settle before the first frame, though it is left out of the video anyway.
        try? await Task.sleep(for: .milliseconds(150))

        let stamp = Self.stamp()
        let folder = Self.folder.appendingPathComponent("Recordings/\(stamp)", isDirectory: true)
        let session = RecordingSession(options: RecordingOptions(
            displayID: target.displayID,
            systemAudio: systemAudio, microphone: microphone, webcam: webcam,
            captureKeys: InputRecorder.hasKeyboardAccess,
            trackCaret: zoomOnTyping && InputRecorder.hasAccessibilityAccess,
            outputFolder: folder, windowID: target.windowID,
            cameraID: webcam ? cameraID : nil, microphoneID: microphone ? microphoneID : nil))
        session.onFailure = { [weak self] error in
            Task { @MainActor in self?.recordingFailed(error) }
        }
        do {
            try await session.start()
        } catch {
            errorMessage = error.localizedDescription
            phase = .idle
            return
        }
        currentTarget = target
        self.session = session
        let since = Date()
        phase = .recording(since: since)
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, case .recording(let started) = self.phase else { return }
                self.elapsed = Int(Date().timeIntervalSince(started))
            }
        }
        NSSound(named: "Tink")?.play()
    }

    private func stop(viaHotKey: Bool) async {
        guard let session else { return }
        timer?.invalidate()
        timer = nil
        self.session = nil
        phase = .saving
        NSSound(named: "Pop")?.play()

        do {
            let bundle = try await session.stop()
            var settings = EditSettings()
            settings.autoZoom = autoZoom
            settings.zoomOnTyping = zoomOnTyping
            // A window or area starts out showing just that part of the screen; the recording keeps all of it.
            if let crop = currentTarget?.crop { settings.style.crop = crop }
            // Stopping from the menu bar means the cursor travelled there; cut that off.
            settings.trimTail = viaHotKey ? 0 : 0.9
            // The automatic edit is the starting point; the editor opens on it and saves changes next to the recording.
            let project = EditProject.auto(for: bundle, settings: settings)
            try project.save(to: bundle.folder)
            library.reload()
            phase = .idle
            bar.hide()
            // Straight to the finished video, playing, with Save and Edit.
            try EditorWindows.shared.showResult(folder: bundle.folder)
        } catch {
            errorMessage = error.localizedDescription
            phase = .idle
        }
    }

    /// Speeding up typing (and zooming on it) needs to know when keys are pressed: Input Monitoring. Only the
    /// moments are recorded, never which keys. Finding the text caret for typing zoom also needs Accessibility.
    /// Neither blocks the recording: without them it still records, with typing at normal speed.
    private func prepareTypingAccess() async {
        if !InputRecorder.hasKeyboardAccess, !UserDefaults.standard.bool(forKey: "askedInputMonitoring") {
            UserDefaults.standard.set(true, forKey: "askedInputMonitoring")
            InputRecorder.requestKeyboardAccess()
        }
        guard zoomOnTyping else { return }
        if !InputRecorder.hasAccessibilityAccess, !UserDefaults.standard.bool(forKey: "askedAccessibility") {
            UserDefaults.standard.set(true, forKey: "askedAccessibility")
            InputRecorder.requestAccessibilityAccess()
        }
    }

    private func recordingFailed(_ error: Error) {
        timer?.invalidate()
        timer = nil
        session = nil
        phase = .idle
        errorMessage = "Recording stopped: \(error.localizedDescription)"
        showBar()
    }

    // MARK: Helpers

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Softcut " + formatter.string(from: Date())
    }

    private func showPermissionHelp() {
        let alert = NSAlert()
        alert.messageText = "Softcut needs Screen Recording access"
        alert.informativeText = "Turn on Softcut in System Settings > Privacy & Security > Screen Recording, then quit and reopen Softcut."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Shown in the menu when Zoom on typing is on but a permission it relies on is missing.
    /// Without Input Monitoring nothing about typing is recorded, so that is said plainly.
    var typingPermissionNotes: [(text: String, pane: String)] {
        var notes: [(String, String)] = []
        if !InputRecorder.hasKeyboardAccess {
            notes.append(("Typing plays at normal speed: allow Input Monitoring", "Privacy_ListenEvent"))
        } else if zoomOnTyping, !InputRecorder.hasAccessibilityAccess {
            notes.append(("Typing zoom will follow the mouse: allow Accessibility to follow the caret", "Privacy_Accessibility"))
        }
        return notes
    }

    func openPrivacySettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    func openFolder() {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Self.folder)
    }

    func openRecordings() { openLibrary() }

    func openLibrary() {
        EditorWindows.shared.showLibrary(library: library) { [weak self] in self?.toggle() }
    }

    /// Opens the newest recording in the editor.
    func editLatest() {
        library.reload()
        guard let latest = library.items.first else { return openLibrary() }
        do { try EditorWindows.shared.openEditor(folder: latest.folder) } catch { errorMessage = error.localizedDescription }
    }
}
