import AVFoundation
import Foundation

/// Records the microphone to a sound file while the finished video plays, for a voice-over.
@MainActor
public final class VoiceOverRecorder {
    public enum Failure: LocalizedError {
        case couldNotStart

        public var errorDescription: String? { "The microphone could not be started." }
    }

    private var recorder: AVAudioRecorder?
    private var started = Date()

    public init() {}

    public var isRecording: Bool { recorder?.isRecording ?? false }

    /// Whether the microphone may be used. The first time, macOS asks the person.
    public static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    public func start(in folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("voiceover-\(UUID().uuidString.prefix(8)).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128_000,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        guard recorder.record() else { throw Failure.couldNotStart }
        self.recorder = recorder
        started = Date()
    }

    /// Stops and returns the file and its length, or nil if nothing was being recorded.
    public func stop() -> (url: URL, duration: Double)? {
        guard let recorder else { return nil }
        let length = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        return (recorder.url, max(length, 0))
    }
}
