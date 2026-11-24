import AVFoundation
import Foundation

/// A short, soft "tick" played at each mouse click. It is made here from a few numbers, so no sound file is needed.
enum ClickSound {
    static let sampleRate = 44_100.0
    static let duration = 0.07

    /// The click as a 16-bit mono WAV file's bytes.
    static func wavData() -> Data {
        let count = Int(sampleRate * duration)
        var samples = [Int16](repeating: 0, count: count)
        var seed: UInt64 = 0x9E3779B97F4A7C15
        var peak = 0.0
        var values = [Double](repeating: 0, count: count)
        for index in 0..<count {
            let t = Double(index) / sampleRate
            // A burst of noise for the touch, and a falling tone for the body of the sound.
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let noise = (Double(seed >> 33) / Double(1 << 31)) * 2 - 1
            let touch = noise * exp(-t / 0.0025) * 0.7
            let tone = sin(2 * .pi * (1500 - 4000 * t) * t) * exp(-t / 0.012) * 0.6
            values[index] = touch + tone
            peak = max(peak, abs(values[index]))
        }
        for index in 0..<count { samples[index] = Int16((values[index] / max(peak, 0.001) * 0.8 * 32767).rounded()) }

        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { var little = value.littleEndian; withUnsafeBytes(of: &little) { data.append(contentsOf: $0) } }
        let byteCount = UInt32(count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(36 + byteCount)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate) * 2); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(byteCount)
        for sample in samples { append(sample) }
        return data
    }

    /// The click as a file on disk, made once.
    static func fileURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("glide-click-v1.wav")
        if !FileManager.default.fileExists(atPath: url.path) { try wavData().write(to: url, options: .atomic) }
        return url
    }
}

extension EditPlan {
    /// When each mouse click lands in the finished video, in seconds, in order. Clicks in cut parts are left out.
    public func clickTimes() -> [Double] {
        var times: [Double] = []
        var outputStart = 0.0
        for segment in timeMap.segments {
            if let clicks = sourcePlans[segment.sourceID]?.clicks {
                for click in clicks where click.t >= segment.sourceStart && click.t < segment.sourceEnd {
                    times.append(outputStart + (click.t - segment.sourceStart) / segment.speed)
                }
            }
            outputStart += segment.outputDuration
        }
        return times.sorted()
    }
}

extension CompositionBuilder {
    /// Adds the sounds that are not part of the recordings: music, click sounds and voice-overs.
    /// Done after the picture is laid out, so changing the speed of a clip does not stretch them.
    static func addExtraAudio(to composition: AVMutableComposition, plan: EditPlan, total: CMTime,
                              into tracks: inout [(role: AudioRole, track: AVMutableCompositionTrack)]) async -> [AVAsset] {
        var assets: [AVAsset] = []
        let totalSeconds = total.seconds
        func time(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 60_000) }

        func soundTrack(of url: URL) async -> (asset: AVURLAsset, track: AVAssetTrack, duration: Double)? {
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let asset = AVURLAsset(url: url)
            guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
                  let duration = try? await asset.load(.duration).seconds, duration > 0.01 else { return nil }
            return (asset, track, duration)
        }
        func newTrack(_ role: AudioRole) -> AVMutableCompositionTrack? {
            guard let created = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }
            tracks.append((role, created))
            return created
        }

        if let music = plan.audio.music, let sound = await soundTrack(of: URL(fileURLWithPath: music.path)), let target = newTrack(.music) {
            assets.append(sound.asset)
            var position = 0.0
            while position < totalSeconds - 0.001 {
                let length = min(sound.duration, totalSeconds - position)
                try? target.insertTimeRange(CMTimeRange(start: .zero, duration: time(length)), of: sound.track, at: time(position))
                position += length
                if !music.loops { break }
            }
        }

        if plan.audio.clickSounds, let url = try? ClickSound.fileURL(), let click = await soundTrack(of: url), let target = newTrack(.clicks) {
            assets.append(click.asset)
            var free = 0.0
            for moment in plan.clickTimes() where moment >= free && moment < totalSeconds {
                let length = min(click.duration, totalSeconds - moment)
                try? target.insertTimeRange(CMTimeRange(start: .zero, duration: time(length)), of: click.track, at: time(moment))
                free = moment + click.duration
            }
        }

        for voice in plan.audio.voiceOvers where voice.start < totalSeconds {
            guard let sound = await soundTrack(of: URL(fileURLWithPath: voice.path)), let target = newTrack(.voiceOver(voice.id)) else { continue }
            assets.append(sound.asset)
            let length = min(voice.duration, sound.duration, totalSeconds - voice.start)
            try? target.insertTimeRange(CMTimeRange(start: .zero, duration: time(length)), of: sound.track, at: time(max(0, voice.start)))
        }
        return assets
    }
}
