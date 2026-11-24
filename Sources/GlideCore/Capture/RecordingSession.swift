import AppKit
import AVFoundation
import ScreenCaptureKit

public struct RecordingOptions: Sendable {
    public var displayID: CGDirectDisplayID?
    public var fps: Int
    public var systemAudio: Bool
    public var microphone: Bool
    public var webcam: Bool
    /// Record key-press times (never which keys) so the editor can zoom while typing.
    public var captureKeys: Bool
    /// Also record the text caret position while typing. Needs Accessibility permission.
    public var trackCaret: Bool
    public var outputFolder: URL
    /// Record only this window (the display is still the one it is on). Nil records everything on the display.
    public var windowID: CGWindowID?
    /// Which camera and microphone to use; nil is the system's choice.
    public var cameraID: String?
    public var microphoneID: String?

    public init(displayID: CGDirectDisplayID? = nil, fps: Int = 60, systemAudio: Bool = false,
                microphone: Bool = false, webcam: Bool = false, captureKeys: Bool = false,
                trackCaret: Bool = false, outputFolder: URL, windowID: CGWindowID? = nil,
                cameraID: String? = nil, microphoneID: String? = nil) {
        self.windowID = windowID
        self.cameraID = cameraID
        self.microphoneID = microphoneID
        self.displayID = displayID
        self.fps = fps
        self.systemAudio = systemAudio
        self.microphone = microphone
        self.webcam = webcam
        self.captureKeys = captureKeys
        self.trackCaret = trackCaret
        self.outputFolder = outputFolder
    }
}

/// One recording from start to stop. Produces a `RecordingBundle` folder on disk.
public final class RecordingSession: @unchecked Sendable {
    public private(set) var isRunning = false
    public var onFailure: ((Error) -> Void)?

    private let options: RecordingOptions
    private let capture = ScreenCapture()
    private var webcam: WebcamCapture?
    private var input: InputRecorder?
    private var display: SCDisplay?
    private var displayFrame = CGRect.zero
    private var pixelScale = 1.0
    private var startedAt = Date()
    private var caretTracked = false

    public init(options: RecordingOptions) {
        self.options = options
    }

    public static func hasScreenRecordingPermission() -> Bool { CGPreflightScreenCaptureAccess() }

    @discardableResult
    public static func requestScreenRecordingPermission() -> Bool { CGRequestScreenCaptureAccess() }

    public static func availableDisplays() async throws -> [SCDisplay] {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true).displays
    }

    public func start() async throws {
        guard !isRunning else { return }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let wanted = options.displayID ?? CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == wanted }) ?? content.displays.first else {
            throw GlideError.noDisplay
        }
        self.display = display

        // Match the display's AppKit frame so mouse positions can be normalized.
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == display.displayID
        }
        displayFrame = screen?.frame ?? CGRect(x: 0, y: 0, width: display.width, height: display.height)
        pixelScale = screen.map { Double($0.backingScaleFactor) } ?? 2

        try FileManager.default.createDirectory(at: options.outputFolder, withIntermediateDirectories: true)

        // The camera is started first: it takes a moment to warm up, and its frames are
        // lined up with the screen by timestamp afterwards.
        if options.webcam {
            let webcam = WebcamCapture()
            try webcam.start(outputURL: options.outputFolder.appendingPathComponent("webcam.mov"), deviceID: options.cameraID)
            self.webcam = webcam
        }

        // Keep our own windows (the recording controls) out of the video.
        let ownApp = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        // One window: the display with only that window on it, so windows in front of it stay out of the video.
        let filter: SCContentFilter
        if let windowID = options.windowID, let window = content.windows.first(where: { $0.windowID == windowID }) {
            filter = SCContentFilter(display: display, including: [window])
        } else {
            filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])
        }

        let input = InputRecorder(displayFrame: displayFrame, displayBounds: CGDisplayBounds(display.displayID),
                                  options: .init(captureKeys: options.captureKeys, trackFocus: options.trackCaret))
        self.input = input
        caretTracked = options.captureKeys && options.trackCaret && InputRecorder.hasAccessibilityAccess
        capture.onStreamStopped = { [weak self] error in
            self?.isRunning = false
            self?.onFailure?(error)
        }
        startedAt = Date()
        do {
            try await capture.start(
                filter: filter,
                pixelWidth: Int(Double(display.width) * pixelScale),
                pixelHeight: Int(Double(display.height) * pixelScale),
                fps: options.fps,
                systemAudio: options.systemAudio,
                microphone: options.microphone,
                microphoneID: options.microphoneID,
                outputURL: options.outputFolder.appendingPathComponent("screen.mov")
            )
        } catch {
            // Do not leave the camera light on if the screen could not start.
            _ = try? await webcam?.stop()
            webcam = nil
            throw error
        }
        input.start()
        isRunning = true
    }

    /// Stops capture and returns the finished recording folder contents.
    public func stop() async throws -> RecordingBundle {
        guard isRunning, let input, let display else { throw GlideError.noFramesCaptured }
        isRunning = false
        let stoppedAt = HostClock.now
        let result = try await capture.stop(endTime: stoppedAt)

        // A webcam that fails to save should not lose the screen recording.
        var webcamFile: String?
        var webcamOffset: Double?
        if let webcam {
            self.webcam = nil
            if let saved = try? await webcam.stop() {
                webcamFile = "webcam.mov"
                webcamOffset = saved.firstFrameTime - result.firstFrameTime
            }
        }

        let bundleFolder = options.outputFolder
        let (log, cursors) = input.stop(origin: result.firstFrameTime,
                                        writingCursorsTo: bundleFolder.appendingPathComponent("cursors", isDirectory: true))
        let manifest = RecordingManifest(
            createdAt: startedAt,
            displayID: display.displayID,
            displayWidth: displayFrame.width,
            displayHeight: displayFrame.height,
            pixelScale: pixelScale,
            duration: result.endTime - result.firstFrameTime,
            hasSystemAudio: options.systemAudio,
            hasMicrophone: options.microphone,
            webcamFile: webcamFile,
            webcamOffset: webcamOffset,
            keysCaptured: options.captureKeys,
            caretTracked: caretTracked
        )
        let bundle = RecordingBundle(folder: bundleFolder, manifest: manifest, input: log, cursors: cursors)
        try bundle.save()
        return bundle
    }
}
