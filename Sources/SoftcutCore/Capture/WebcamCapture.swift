import AVFoundation

/// Camera permission, for apps that need to ask before a recording starts.
public enum CameraAccess {
    public static var isGranted: Bool { AVCaptureDevice.authorizationStatus(for: .video) == .authorized }
    public static var isDenied: Bool {
        [.denied, .restricted].contains(AVCaptureDevice.authorizationStatus(for: .video))
    }

    /// Shows the system prompt the first time; afterwards just reports the saved answer.
    public static func request() async -> Bool { await AVCaptureDevice.requestAccess(for: .video) }
}

/// Records the camera into its own .mov. Frames keep their capture timestamps, converted to
/// the host clock so they can be lined up with the screen video afterwards. Microphone audio
/// is not recorded here; the screen recording already carries it.
final class WebcamCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    struct Result {
        /// Host-clock time of the first webcam frame.
        let firstFrameTime: Double
    }

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.softcut.webcam", qos: .userInteractive)
    private var outputURL: URL?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var firstFrameHostTime: Double?
    private var lastPresentationTime = CMTime.invalid
    private var failure: Error?

    static var authorization: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .video) }

    static func requestAccess() async -> Bool { await AVCaptureDevice.requestAccess(for: .video) }

    func start(outputURL: URL, deviceID: String? = nil) throws {
        guard Self.authorization == .authorized else {
            throw SoftcutError.cameraUnavailable("Camera access is off for Softcut. Turn it on in System Settings > Privacy & Security > Camera.")
        }
        guard let device = deviceID.flatMap({ AVCaptureDevice(uniqueID: $0) }) ?? AVCaptureDevice.userPreferredCamera ?? AVCaptureDevice.default(for: .video) else {
            throw SoftcutError.cameraUnavailable("No camera was found.")
        }
        self.outputURL = outputURL

        let deviceInput = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        guard session.canAddInput(deviceInput) else {
            session.commitConfiguration()
            throw SoftcutError.cameraUnavailable("\(device.localizedName) cannot be used right now.")
        }
        session.addInput(deviceInput)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = false
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw SoftcutError.cameraUnavailable("The camera output could not be set up.")
        }
        session.addOutput(output)
        session.commitConfiguration()

        // Blocks until the camera is running, which can take a moment.
        session.startRunning()
    }

    func stop() async throws -> Result {
        session.stopRunning()
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard let writer, let input, let first = firstFrameHostTime else {
                    continuation.resume(throwing: SoftcutError.cameraUnavailable("The camera produced no frames."))
                    return
                }
                input.markAsFinished()
                if lastPresentationTime.isValid { writer.endSession(atSourceTime: lastPresentationTime) }
                writer.finishWriting {
                    if writer.status == .completed {
                        continuation.resume(returning: Result(firstFrameTime: first))
                    } else {
                        let detail = writer.error?.localizedDescription ?? self.failure?.localizedDescription ?? "unknown error"
                        continuation.resume(throwing: SoftcutError.cameraUnavailable("Saving the webcam video failed: \(detail)"))
                    }
                }
            }
        }
    }

    // MARK: AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard sampleBuffer.isValid, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = sampleBuffer.presentationTimeStamp

        if writer == nil {
            do {
                try makeWriter(width: CVPixelBufferGetWidth(pixels), height: CVPixelBufferGetHeight(pixels), start: time)
            } catch {
                failure = error
                return
            }
        }
        guard let writer, writer.status == .writing, let input, input.isReadyForMoreMediaData else { return }
        if input.append(sampleBuffer) { lastPresentationTime = time }
    }

    private func makeWriter(width: Int, height: Int, start: CMTime) throws {
        guard let outputURL else { throw SoftcutError.cameraUnavailable("No output file.") }
        try? FileManager.default.removeItem(at: outputURL)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: 30,
            ] as [String: Any],
        ])
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw SoftcutError.cameraUnavailable("The webcam video format is not supported.") }
        writer.add(input)
        guard writer.startWriting() else {
            throw SoftcutError.cameraUnavailable(writer.error?.localizedDescription ?? "could not start writing")
        }
        writer.startSession(atSourceTime: start)
        self.writer = writer
        self.input = input

        // Camera timestamps are on the session's clock; the screen uses the host clock.
        var hostTime = start
        if let clock = session.synchronizationClock {
            hostTime = CMSyncConvertTime(start, from: clock, to: CMClockGetHostTimeClock())
        }
        firstFrameHostTime = hostTime.seconds
    }
}
