import Foundation

/// Backing music that comes with Softcut. Each track is synthesized on this Mac the first time it is used, so nothing is
/// downloaded and there is nothing to license. Every track loops without a seam.
public enum BuiltInMusic {
    public struct Track: Identifiable, Equatable, Sendable {
        public let id: String
        public let name: String
        let beatsPerMinute: Double
        /// One chord to a bar, as MIDI notes.
        let chords: [[Int]]
        var arpeggio = false
        var kick = false
        var hats = false
        var bass = false
    }

    private static let maj7C = [60, 64, 67, 71], am7 = [57, 60, 64, 67], fmaj7 = [53, 57, 60, 64], g6 = [55, 59, 62, 64]
    private static let cMajor = [60, 64, 67, 72], gMajor = [55, 59, 62, 67], aMinor = [57, 60, 64, 69], fMajor = [53, 57, 60, 65]
    private static let dMinor = [50, 57, 62, 65], bFlat = [46, 53, 58, 62]

    public static let tracks = [
        Track(id: "calm", name: "Calm", beatsPerMinute: 72, chords: [maj7C, am7, fmaj7, g6]),
        Track(id: "focus", name: "Focus", beatsPerMinute: 90, chords: [am7, fmaj7, maj7C, g6], arpeggio: true, hats: true),
        Track(id: "bright", name: "Bright", beatsPerMinute: 112, chords: [cMajor, gMajor, aMinor, fMajor], arpeggio: true, kick: true, hats: true),
        Track(id: "drive", name: "Drive", beatsPerMinute: 124, chords: [dMinor, bFlat, fMajor, cMajor], kick: true, hats: true, bass: true),
    ]

    private static let sampleRate = 44_100
    private static let beatsPerBar = 4.0

    /// The track's sound file, made the first time it is asked for.
    public static func url(for track: Track, in folder: URL? = nil) throws -> URL {
        let folder = folder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Softcut/Music", isDirectory: true)
        let file = folder.appendingPathComponent("\(track.id).wav")
        if FileManager.default.fileExists(atPath: file.path) { return file }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try wav(samples(of: track)).write(to: file, options: .atomic)
        return file
    }

    /// The track as left and right samples, one pair after another. Sounds that ring past the end wrap to the start, so it loops.
    static func samples(of track: Track) -> [Float] {
        let beat = 60 / track.beatsPerMinute
        let bar = beat * beatsPerBar
        let bars = max(1, Int((24 / (bar * Double(track.chords.count))).rounded(.up))) * track.chords.count
        let frames = Int(Double(bars) * bar * Double(sampleRate))
        var left = [Float](repeating: 0, count: frames)
        var right = left

        func add(at start: Double, length: Double, pan: Float, gain: Float, _ wave: (Double) -> Double) {
            let first = Int(start * Double(sampleRate))
            for i in 0..<Int(length * Double(sampleRate)) {
                let value = Float(wave(Double(i) / Double(sampleRate))) * gain
                left[(first + i) % frames] += value * (1 - pan)
                right[(first + i) % frames] += value * pan
            }
        }
        func hertz(_ note: Int) -> Double { 440 * pow(2, (Double(note) - 69) / 12) }

        var noise: UInt64 = 0x9E37_79B9_7F4A_7C15
        func nextNoise() -> Double {
            noise = noise &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(noise >> 40) / Double(1 << 24) * 2 - 1
        }

        for index in 0..<bars {
            let chord = track.chords[index % track.chords.count]
            let start = Double(index) * bar

            // A soft pad, with a slow swell in and out across the bar.
            for (voice, note) in chord.enumerated() {
                let f = hertz(note)
                let length = bar * 1.25
                add(at: start, length: length, pan: voice % 2 == 0 ? 0.42 : 0.58, gain: 0.11) { t in
                    let swell = min(t / 0.5, 1) * min((length - t) / 0.7, 1)
                    return swell * (sin(2 * .pi * f * t) + 0.35 * sin(2 * .pi * f * 2.003 * t) + 0.12 * sin(2 * .pi * f * 3.001 * t))
                }
            }

            if track.arpeggio {
                let step = beat / 2
                for i in 0..<Int(beatsPerBar * 2) {
                    let note = chord[[0, 2, 1, 3, 2, 1, 3, 2][i % 8]] + 12
                    let f = hertz(note)
                    add(at: start + Double(i) * step, length: 0.7, pan: i % 2 == 0 ? 0.35 : 0.65, gain: 0.1) { t in
                        exp(-t * 6) * min(t / 0.004, 1) * (sin(2 * .pi * f * t) + 0.25 * sin(4 * .pi * f * t))
                    }
                }
            }

            if track.bass {
                let f = hertz(chord[0] - 12)
                for i in 0..<Int(beatsPerBar * 2) {
                    add(at: start + Double(i) * beat / 2, length: beat / 2, pan: 0.5, gain: 0.2) { t in
                        exp(-t * 5) * min(t / 0.005, 1) * (sin(2 * .pi * f * t) + 0.3 * sin(4 * .pi * f * t))
                    }
                }
            }

            if track.kick {
                for i in 0..<Int(beatsPerBar) {
                    add(at: start + Double(i) * beat, length: 0.28, pan: 0.5, gain: 0.34) { t in
                        exp(-t * 16) * sin(2 * .pi * (48 * t + 9 * (1 - exp(-t * 28))))
                    }
                }
            }

            if track.hats {
                for i in 0..<Int(beatsPerBar * 2) where i % 2 == 1 || track.kick {
                    var previous = 0.0
                    add(at: start + Double(i) * beat / 2, length: 0.07, pan: 0.6, gain: 0.03) { t in
                        // The difference of successive noise leaves only the highs.
                        let sample = nextNoise()
                        defer { previous = sample }
                        return exp(-t * 60) * (sample - previous)
                    }
                }
            }
        }

        // Keeps every track at the same comfortable level.
        let peak = max(left.lazy.map(abs).max() ?? 1, right.lazy.map(abs).max() ?? 1, 0.001)
        var stereo = [Float](repeating: 0, count: frames * 2)
        for i in 0..<frames {
            stereo[i * 2] = left[i] / peak * 0.8
            stereo[i * 2 + 1] = right[i] / peak * 0.8
        }
        return stereo
    }

    private static func wav(_ stereo: [Float]) -> Data {
        var data = Data(capacity: 44 + stereo.count * 2)
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func u32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(stereo.count * 2)
        text("RIFF"); u32(36 + bytes); text("WAVE")
        text("fmt "); u32(16); u16(1); u16(2); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 4)); u16(4); u16(16)
        text("data"); u32(bytes)
        for sample in stereo { withUnsafeBytes(of: Int16(max(-1, min(1, sample)) * 32_767).littleEndian) { data.append(contentsOf: $0) } }
        return data
    }
}
