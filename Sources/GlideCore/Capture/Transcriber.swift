import AVFoundation
import Foundation
import Speech

/// Turns what was said in a recording into captions, with Apple's speech recognizer.
/// Recognition happens on this Mac only: the sound is never sent anywhere.
public enum Transcriber {
    public enum Failure: LocalizedError {
        case notAllowed
        case unavailable(String)
        case noVoice
        case failed(String)

        public var errorDescription: String? {
            switch self {
            case .notAllowed: return "Softcut needs permission for speech recognition. Allow it in System Settings, Privacy & Security, Speech Recognition."
            case .unavailable(let reason): return reason
            case .noVoice: return "This recording has no microphone sound to turn into captions. Turn on Microphone in Softcut's menu before recording."
            case .failed(let reason): return "Captions could not be made: \(reason)"
            }
        }
    }

    /// Languages that can be recognized on this Mac without sending sound away.
    public static func onDeviceLocales() -> [Locale] {
        SFSpeechRecognizer.supportedLocales()
            .filter { SFSpeechRecognizer(locale: $0)?.supportsOnDeviceRecognition == true }
            .sorted { ($0.localizedString(forIdentifier: $0.identifier) ?? "") < ($1.localizedString(forIdentifier: $1.identifier) ?? "") }
    }

    /// Whether speech recognition may be used. The first time, macOS asks the person.
    /// Only call this from the app: a program without the usage description in its Info.plist is stopped by macOS.
    public static func requestAccess() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
        default: return false
        }
    }

    /// Captions for one recording, in that recording's seconds.
    public static func transcribe(_ bundle: RecordingBundle, source: UUID?, locale: Locale) async throws -> [CaptionLine] {
        guard bundle.manifest.hasMicrophone else { throw Failure.noVoice }
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw Failure.unavailable("Speech recognition does not support that language.")
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw Failure.unavailable("This Mac cannot recognize that language without sending sound to Apple, so Softcut will not. Pick another language, or download it in System Settings, Keyboard, Dictation.")
        }

        let voice = try await extractVoice(of: bundle)
        defer { try? FileManager.default.removeItem(at: voice) }

        let request = SFSpeechURLRecognitionRequest(url: voice)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true

        let words: [SpokenWord] = try await withCheckedThrowingContinuation { continuation in
            var finished = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !finished else { return }
                if let result, result.isFinal {
                    finished = true
                    continuation.resume(returning: result.bestTranscription.segments.map {
                        SpokenWord(text: $0.substring, start: $0.timestamp, duration: $0.duration)
                    })
                } else if let error {
                    finished = true
                    // Silence is not a failure: it just has no words.
                    let message = error.localizedDescription
                    if message.localizedCaseInsensitiveContains("no speech") {
                        continuation.resume(returning: [])
                    } else {
                        continuation.resume(throwing: Failure.failed(message))
                    }
                }
            }
        }
        return CaptionBuilder.lines(from: words, source: source)
    }

    /// The microphone's sound as a file of its own, lined up with the recording's time.
    private static func extractVoice(of bundle: RecordingBundle) async throws -> URL {
        let asset = AVURLAsset(url: bundle.videoURL)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        // The recorder writes system audio first, then the microphone.
        guard let track = bundle.manifest.hasMicrophone ? tracks.last : nil else { throw Failure.noVoice }
        let duration = try await asset.load(.duration)

        let composition = AVMutableComposition()
        guard let target = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw Failure.failed("could not prepare the sound")
        }
        try target.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("glide-voice-\(UUID().uuidString).m4a")
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw Failure.failed("could not prepare the sound")
        }
        try await session.export(to: url, as: .m4a)
        withExtendedLifetime(asset) {}
        return url
    }
}
