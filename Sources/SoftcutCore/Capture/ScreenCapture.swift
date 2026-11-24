import AVFoundation
import CoreMedia
import ScreenCaptureKit

/// Seconds on the host clock. ScreenCaptureKit stamps frames with this clock and
/// NSEvent timestamps use the same uptime base, so input and video line up.
enum HostClock {
    static var now: Double { CMClockGetTime(CMClockGetHostTimeClock()).seconds }
}

/// Records one display (without the cursor) plus optional system audio and
/// microphone into a single .mov: one video track and up to two audio tracks.
final class ScreenCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    struct Result {
        /// Host-clock time of the first video frame; input events are measured from here.
        let firstFrameTime: Double
        let endTime: Double
    }

    /// Called on a background queue if the system stops the stream, for example
    /// when the display is disconnected or permission is revoked.
    var onStreamStopped: ((Error) -> Void)?

    private let queue = DispatchQueue(label: "app.softcut.capture", qos: .userInteractive)
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var microphoneInput: AVAssetWriterInput?
    private var sessionStart: CMTime?
    private var lastVideoTime = CMTime.invalid
    private(set) var droppedFrames = 0

    func start(filter: SCContentFilter, pixelWidth: Int, pixelHeight: Int, fps: Int,
               systemAudio: Bool, microphone: Bool, microphoneID: String? = nil, outputURL: URL) async throws {
        let width = pixelWidth & ~1
        let height = pixelHeight & ~1

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Int(Double(width * height * fps) * 0.05),
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: fps * 2,
                AVVideoAllowFrameReorderingKey: false,
            ] as [String: Any],
        ])
        video.expectsMediaDataInRealTime = true
        writer.add(video)

        func addAudioInput() -> AVAssetWriterInput {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000,
            ])
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            return input
        }
        let systemAudioInput = systemAudio ? addAudioInput() : nil
        let microphoneInput = microphone ? addAudioInput() : nil

        guard writer.startWriting() else {
            throw SoftcutError.writerFailed(writer.error?.localizedDescription ?? "could not start")
        }
        self.writer = writer
        self.videoInput = video
        self.systemAudioInput = systemAudioInput
        self.microphoneInput = microphoneInput

        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.showsCursor = false
        config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        config.colorSpaceName = CGColorSpace.sRGB
        config.queueDepth = 8
        config.capturesAudio = systemAudio
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        config.captureMicrophone = microphone
        if microphone, let microphoneID { config.microphoneCaptureDeviceID = microphoneID }

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if systemAudio { try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue) }
        if microphone { try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue) }
        try await stream.startCapture()
        self.stream = stream
    }

    func stop(endTime: Double) async throws -> Result {
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard let writer, let start = sessionStart else {
                    writer?.cancelWriting()
                    continuation.resume(throwing: SoftcutError.noFramesCaptured)
                    return
                }
                videoInput?.markAsFinished()
                systemAudioInput?.markAsFinished()
                microphoneInput?.markAsFinished()
                let end = CMTimeMaximum(CMTime(seconds: endTime, preferredTimescale: 1_000_000_000), lastVideoTime)
                writer.endSession(atSourceTime: end)
                writer.finishWriting {
                    if writer.status == .completed {
                        continuation.resume(returning: Result(firstFrameTime: start.seconds, endTime: end.seconds))
                    } else {
                        continuation.resume(throwing: SoftcutError.writerFailed(writer.error?.localizedDescription ?? "unknown error"))
                    }
                }
            }
        }
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid, let writer, writer.status == .writing else { return }
        switch type {
        case .screen:
            guard Self.isCompleteFrame(sampleBuffer), let videoInput else { return }
            let time = sampleBuffer.presentationTimeStamp
            if sessionStart == nil {
                writer.startSession(atSourceTime: time)
                sessionStart = time
            }
            if videoInput.isReadyForMoreMediaData {
                videoInput.append(sampleBuffer)
                lastVideoTime = time
            } else {
                droppedFrames += 1
            }
        case .audio:
            appendAudio(sampleBuffer, to: systemAudioInput)
        case .microphone:
            appendAudio(sampleBuffer, to: microphoneInput)
        @unknown default:
            break
        }
    }

    private func appendAudio(_ sampleBuffer: CMSampleBuffer, to input: AVAssetWriterInput?) {
        guard let input, let start = sessionStart,
              sampleBuffer.presentationTimeStamp >= start,
              input.isReadyForMoreMediaData else { return }
        input.append(sampleBuffer)
    }

    /// ScreenCaptureKit also delivers idle and blank frames; only complete frames carry new pixels.
    private static func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: rawStatus) else { return false }
        return status == .complete
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStreamStopped?(error)
    }
}
