import AVFoundation
import XCTest
@testable import GlideCore

final class ExtraAudioModelTests: XCTestCase {
    func testOldProjectsWithoutTheNewSoundSettingsStillOpen() throws {
        let audio = try JSONDecoder().decode(AudioSettings.self, from: Data(#"{"volume":0.8,"muteMicrophone":true}"#.utf8))
        XCTAssertEqual(audio.volume, 0.8, accuracy: 1e-9)
        XCTAssertTrue(audio.muteMicrophone)
        XCTAssertNil(audio.music)
        XCTAssertFalse(audio.clickSounds)
        XCTAssertTrue(audio.voiceOvers.isEmpty)
    }

    func testMusicAndVoiceOversSurviveSaving() throws {
        var audio = AudioSettings()
        audio.music = BackingMusic(path: "/tmp/song.mp3", name: "song", volume: 0.4, loops: false)
        audio.clickSounds = true
        audio.voiceOvers = [VoiceOver(path: "/tmp/v.m4a", start: 2.5, duration: 4, volume: 0.9)]
        let again = try JSONDecoder().decode(AudioSettings.self, from: JSONEncoder().encode(audio))
        XCTAssertEqual(again, audio)
    }

    func testOnlyChangesToWhichSoundsExistNeedAFreshPreview() {
        var audio = AudioSettings()
        audio.music = BackingMusic(path: "/tmp/a.mp3", name: "a")
        let before = audio.structure

        var louder = audio
        louder.volume = 0.5
        louder.music?.volume = 0.9
        louder.clickVolume = 0.1
        louder.muteMicrophone = true
        XCTAssertEqual(louder.structure, before, "volumes and mutes apply while it plays")

        var other = audio
        other.music = BackingMusic(path: "/tmp/b.mp3", name: "b")
        XCTAssertNotEqual(other.structure, before)
        var clicks = audio
        clicks.clickSounds = true
        XCTAssertNotEqual(clicks.structure, before)
        var voice = audio
        voice.voiceOvers = [VoiceOver(path: "/tmp/v.m4a", start: 1, duration: 2)]
        XCTAssertNotEqual(voice.structure, before)
    }

    func testTheClickSoundIsAValidShortWAV() throws {
        let data = ClickSound.wavData()
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE")
        let samples = (data.count - 44) / 2
        XCTAssertEqual(Double(samples) / ClickSound.sampleRate, ClickSound.duration, accuracy: 0.001)
        // Audible, but not clipped.
        let peak = data.dropFirst(44).withUnsafeBytes { raw in raw.bindMemory(to: Int16.self).map { abs(Int($0)) }.max() ?? 0 }
        XCTAssertGreaterThan(peak, 10_000)
        XCTAssertLessThan(peak, 32_000)
    }

    func testClickTimesFollowCutsAndSpeed() {
        let clicks = [3.0, 6.0, 10.0, 12.0].map { ClickEvent(t: $0, x: 0.5, y: 0.5, down: true) }
        let segments = [
            TimeSegment(sourceStart: 0, sourceEnd: 5),                    // output 0...5, click at 3
            TimeSegment(sourceStart: 8, sourceEnd: 14, speed: 2),         // output 5...8, source 10 -> 6, 12 -> 7
        ]
        let map = TimeMap(segments: segments)
        let plan = EditPlan(settings: EditSettings(), timeMap: map, zooms: [], clicks: clicks,
                            cursorTrack: SampledTrack(rate: 120, samples: [SIMD2(0.5, 0.5)]),
                            cameraTrack: SampledTrack(rate: 120, samples: [SIMD3(1, 0.5, 0.5)]))
        let times = plan.clickTimes()
        // The click at 6 s was cut, so three remain.
        XCTAssertEqual(times.count, 3)
        XCTAssertEqual(times[0], 3, accuracy: 1e-9)
        XCTAssertEqual(times[1], 5 + (10 - 8) / 2.0, accuracy: 1e-9)
        XCTAssertEqual(times[2], 5 + (12 - 8) / 2.0, accuracy: 1e-9)
    }
}

/// Builds and renders real sound, which needs the video frameworks (so these run outside the sandbox).
@MainActor
final class ExtraAudioRenderTests: XCTestCase {
    private var folder: URL!
    private var bundle: RecordingBundle!
    private var tone: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("glide-audio-test-\(UUID().uuidString)")
        bundle = try DemoRecording.make(in: folder)
        tone = folder.appendingPathComponent("tone.wav")
        try ClickSound.wavData().write(to: tone)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func project(_ change: (inout EditProject) -> Void) -> EditProject {
        var project = EditProject.auto(for: bundle)
        change(&project)
        return project
    }

    func testMusicClicksAndVoiceOversBecomeTracksAndTheVideoKeepsItsLength() async throws {
        let plain = EditProject.auto(for: bundle)
        let withSound = project {
            $0.audio.music = BackingMusic(path: tone.path, name: "tone")
            $0.audio.clickSounds = true
            $0.audio.voiceOvers = [VoiceOver(path: tone.path, start: 2, duration: 0.07)]
        }
        let sources = SourceSet(primary: bundle)
        let base = try await CompositionBuilder.build(sources: sources, plan: AutoEditor.makePlan(sources: sources, project: plain))
        let built = try await CompositionBuilder.build(sources: sources, plan: AutoEditor.makePlan(sources: sources, project: withSound))

        let roles = built.audioTracks.map(\.role)
        XCTAssertTrue(roles.contains(.music))
        XCTAssertTrue(roles.contains(.clicks))
        XCTAssertEqual(roles.filter { if case .voiceOver = $0 { return true } else { return false } }.count, 1)
        XCTAssertEqual(built.composition.duration.seconds, base.composition.duration.seconds, accuracy: 0.05,
                       "sounds never make the video longer")
        XCTAssertEqual(built.audioMix?.inputParameters.count, built.audioTracks.count)

        // The music repeats to cover the whole video.
        let music = try XCTUnwrap(built.audioTracks.first { $0.role == .music }?.track)
        XCTAssertEqual(music.timeRange.duration.seconds, built.composition.duration.seconds, accuracy: 0.1)
    }

    func testMusicThatDoesNotLoopPlaysOnce() async throws {
        let once = project { $0.audio.music = BackingMusic(path: tone.path, name: "tone", loops: false) }
        let sources = SourceSet(primary: bundle)
        let built = try await CompositionBuilder.build(sources: sources, plan: AutoEditor.makePlan(sources: sources, project: once))
        let music = try XCTUnwrap(built.audioTracks.first { $0.role == .music }?.track)
        XCTAssertEqual(music.timeRange.duration.seconds, ClickSound.duration, accuracy: 0.01)
    }

    func testMissingSoundFilesAreSkippedInsteadOfBreakingTheVideo() async throws {
        let broken = project {
            $0.audio.music = BackingMusic(path: "/nonexistent/song.mp3", name: "gone")
            $0.audio.voiceOvers = [VoiceOver(path: "/nonexistent/v.m4a", start: 1, duration: 2)]
        }
        let sources = SourceSet(primary: bundle)
        let built = try await CompositionBuilder.build(sources: sources, plan: AutoEditor.makePlan(sources: sources, project: broken))
        XCTAssertTrue(built.audioTracks.isEmpty)
        XCTAssertGreaterThan(built.composition.duration.seconds, 1)
    }

    func testVolumeChangesApplyInPlaceButNewSoundsRebuild() async throws {
        let start = project { $0.audio.music = BackingMusic(path: tone.path, name: "tone") }
        let session = try await PreviewSession.make(bundle: bundle, project: start, previewWidth: 480)
        var louder = start
        louder.audio.volume = 0.6
        louder.audio.music?.volume = 0.8
        XCTAssertTrue(session.update(project: louder))

        var clicks = start
        clicks.audio.clickSounds = true
        XCTAssertFalse(session.update(project: clicks))
    }

    func testExportingLeavesOnlyTheFinishedFile() async throws {
        let plan = AutoEditor.makePlan(for: bundle, project: project { $0.settings.style.maxOutputWidth = 480 })
        let destination = folder.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try await Exporter.export(bundle: bundle, plan: plan, to: destination.appendingPathComponent("video.mp4"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path), ["video.mp4"])
    }

    func testExportedVideoCarriesTheMix() async throws {
        let withSound = project {
            $0.audio.music = BackingMusic(path: tone.path, name: "tone")
            $0.audio.clickSounds = true
            $0.settings.style.maxOutputWidth = 480
        }
        let plan = AutoEditor.makePlan(for: bundle, project: withSound)
        let output = folder.appendingPathComponent("with-sound.mp4")
        try await Exporter.export(bundle: bundle, plan: plan, to: output)
        let asset = AVURLAsset(url: output)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertFalse(audio.isEmpty, "the exported file has a sound track")
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, plan.outputDuration, accuracy: 0.2)

        // The sound is really there: decode it and look for samples that are not silence.
        let reader = try AVAssetReader(asset: asset)
        let decoded = AVAssetReaderTrackOutput(track: audio[0], outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(decoded)
        XCTAssertTrue(reader.startReading())
        var peak = 0
        while let buffer = decoded.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
            var length = 0
            var pointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer)
            guard let pointer else { continue }
            pointer.withMemoryRebound(to: Int16.self, capacity: length / 2) { samples in
                for index in 0..<(length / 2) { peak = max(peak, abs(Int(samples[index]))) }
            }
        }
        XCTAssertGreaterThan(peak, 300, "the exported mix is silent")
    }
}
