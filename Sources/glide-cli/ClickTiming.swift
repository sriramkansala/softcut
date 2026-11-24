import AVFoundation
import Foundation
import GlideCore

/// `glide-cli click-timing FOLDER`: for each left click, when the mouse, the drawn cursor and the picture each do their
/// part, compared with the moment the button goes down (which is when the click effect and click sound start).
enum ClickTiming {
    static func run(folder: URL) async throws {
        let bundle = try RecordingBundle.load(from: folder)
        let plan = AutoEditor.makePlan(for: bundle, project: EditProject.auto(for: bundle))
        let width = bundle.manifest.displayWidth, height = bundle.manifest.displayHeight
        let clicks = bundle.input.clicks.sorted { $0.t < $1.t }
        let moves = bundle.input.moves

        func points(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { hypot((a.x - b.x) * width, (a.y - b.y) * height) }

        struct Row { let t: Double, x: Double, y: Double, held: Double, rawStill: Double, drawnStill: Double, at50: Double, at16: Double, cameraMove: Double, speedIn: Double }
        var rows: [Row] = []
        for (index, click) in clicks.enumerated() where click.down && click.button == .left {
            let up = clicks[(index + 1)...].first { !$0.down && $0.button == .left }?.t ?? click.t
            let target = SIMD2(click.x, click.y)
            // How long the mouse had been within 2 points of the click before the button went down.
            let lastAway = moves.last { $0.t < click.t && points(SIMD2($0.x, $0.y), target) > 2 }?.t ?? 0
            var drawnAway = click.t
            var probe = click.t
            while probe > max(0, click.t - 2) {
                if points(plan.cursor(at: probe), target) > 2 { break }
                drawnAway = probe
                probe -= 1.0 / 240
            }
            let before = plan.camera(at: click.t - 1.0 / 60), now = plan.camera(at: click.t)
            // How fast the camera is moving the picture at the click, in points of the display per second.
            let cameraMove = hypot((now.centerX - before.centerX) * width, (now.centerY - before.centerY) * height) * 60 * now.scale
            let speedIn = points(plan.cursor(at: click.t), plan.cursor(at: click.t - 1.0 / 60)) * 60
            rows.append(Row(t: click.t, x: click.x, y: click.y, held: up - click.t, rawStill: click.t - lastAway, drawnStill: click.t - drawnAway,
                            at50: points(plan.cursor(at: click.t - 0.05), target), at16: points(plan.cursor(at: click.t - 1.0 / 60), target),
                            cameraMove: cameraMove, speedIn: speedIn))
        }

        // The picture's own reaction: frames around each click, measured in the area around it. The recorded video has no cursor.
        let asset = AVURLAsset(url: bundle.folder.appendingPathComponent("screen.mov"))
        let track = try await asset.loadTracks(withMediaType: .video).first!
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        reader.startReading()
        var reactions = [Double?](repeating: nil, count: rows.count)
        var previous: [[UInt8]] = rows.map { _ in [] }
        var timelines: [[(Double, Int)]] = rows.map { _ in [] }
        while let sample = output.copyNextSampleBuffer() {
            let time = sample.presentationTimeStamp.seconds
            guard let buffer = sample.imageBuffer else { continue }
            var locked = false
            for (index, row) in rows.enumerated() where time >= row.t - 0.2 && time <= row.t + 1.0 {
                if !locked { CVPixelBufferLockBaseAddress(buffer, .readOnly); locked = true }
                let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer), bytes = CVPixelBufferGetBytesPerRow(buffer)
                let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
                let cx = Int(row.x * Double(w)), cy = Int(row.y * Double(h)), r = w / 16
                var gray: [UInt8] = []
                for y in stride(from: max(0, cy - r), to: min(h, cy + r), by: 2) {
                    for x in stride(from: max(0, cx - r), to: min(w, cx + r), by: 2) { gray.append(base[y * bytes + x * 4 + 1]) }
                }
                if previous[index].count == gray.count, reactions[index] == nil, time > row.t - 0.15 {
                    var changed = 0
                    for k in 0..<gray.count where abs(Int(gray[k]) - Int(previous[index][k])) > 12 { changed += 1 }
                    if changed > 12 { reactions[index] = time - row.t }
                }
                if previous[index].count == gray.count {
                    var changed = 0
                    for k in 0..<gray.count where abs(Int(gray[k]) - Int(previous[index][k])) > 12 { changed += 1 }
                    timelines[index].append((time - row.t, changed))
                }
                previous[index] = gray
            }
            if locked { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        }

        print("   click   held  mouseStill  drawnStill  miss@-50ms  miss@-16ms  cursorSpeed  cameraSpeed  pictureChanges")
        for (index, row) in rows.enumerated() {
            let reaction = reactions[index].map { String(format: "%+6.0fms", $0 * 1000) } ?? "      - "
            print(String(format: "%8.2f %4.0fms %8.0fms %9.0fms %9.0fpt %9.0fpt %10.0fpt/s %10.0fpt/s  ", row.t, row.held * 1000, row.rawStill * 1000, row.drawnStill * 1000,
                         row.at50, row.at16, row.speedIn, row.cameraMove) + reaction)
        }
        print("\nPicture changes near each click (ms from button down: changed samples). Button comes up at the 'up' time.")
        for (index, row) in rows.enumerated() {
            let bursts = timelines[index].filter { $0.1 > 12 }.map { String(format: "%+.0f:%d", $0.0 * 1000, $0.1) }.joined(separator: "  ")
            let gaps = zip(timelines[index], timelines[index].dropFirst()).map { $1.0 - $0.0 }
            print(String(format: "%7.2f up %+.0f  frames %d, longest gap %.0fms | ", row.t, row.held * 1000, timelines[index].count, (gaps.max() ?? 0) * 1000) + bursts)
        }

        // What the viewer sees: the cursor's speed on the canvas, 240 times a second, going into each click.
        print("\nCursor speed on screen into each click, including the camera (display pts/s; every 1/60 s, last value is the click):")
        for row in rows {
            func onCanvas(_ t: Double) -> SIMD2<Double> {
                let c = plan.cursor(at: t), v = plan.camera(at: t)
                return SIMD2((c.x - v.centerX) * width * v.scale, (c.y - v.centerY) * height * v.scale)
            }
            var speeds: [String] = []
            for step in stride(from: -18, through: 12, by: 1) {
                let t = row.t + Double(step) / 60
                let d = onCanvas(t) - onCanvas(t - 1.0 / 240)
                speeds.append(String(format: "%.0f", hypot(d.x, d.y) * 240))
            }
            print(String(format: "%7.2f  ", row.t) + speeds.joined(separator: " "))
        }
    }

    /// Exports a recording at 240 frames a second (60 for a long one) with and without the click effect, and compares when the click sound
    /// starts in the finished file with the first frame that shows the effect.
    static func sync(folder: URL, work: URL) async throws {
        let bundle = try RecordingBundle.load(from: folder)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        // The saved edit, cuts and all, since that is what is actually being watched.
        var project = EditProject.open(bundle)
        project.settings.style.fps = bundle.manifest.duration > 30 ? 60 : 240
        project.settings.style.maxOutputWidth = 480
        project.audio.clickSounds = true
        project.audio.clickVolume = 1
        project.settings.style.clickEffect = true
        let with = work.appendingPathComponent("with.mp4"), without = work.appendingPathComponent("without.mp4")
        try await Exporter.export(bundle: bundle, plan: AutoEditor.makePlan(for: bundle, project: project), to: with) { _ in }
        project.settings.style.clickEffect = false
        try await Exporter.export(bundle: bundle, plan: AutoEditor.makePlan(for: bundle, project: project), to: without) { _ in }

        let plan = AutoEditor.makePlan(for: bundle, project: project)
        let expected = plan.clickTimes()

        // The sound: where the samples first get loud after each expected moment.
        let audioAsset = AVURLAsset(url: with)
        let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first!
        let audioReader = try AVAssetReader(asset: audioAsset)
        let audioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsNonInterleaved: false, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1])
        audioReader.add(audioOutput)
        audioReader.startReading()
        var onsets: [Double] = []
        var quietUntil = 0.0
        while let sample = audioOutput.copyNextSampleBuffer(), let block = sample.dataBuffer {
            let start = sample.presentationTimeStamp.seconds
            var length = 0
            var pointer: UnsafeMutablePointer<CChar>?
            CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer)
            let values = UnsafeRawPointer(pointer!).assumingMemoryBound(to: Int16.self)
            for index in 0..<(length / 2) where abs(Int(values[index])) > 1500 {
                let time = start + Double(index) / 48_000
                if time > quietUntil { onsets.append(time) }
                quietUntil = time + 0.1
            }
        }

        // The picture: the first frame after which the two exports differ, for each click.
        func reader(_ url: URL) async throws -> (AVAssetReader, AVAssetReaderTrackOutput) {
            let asset = AVURLAsset(url: url)
            let track = try await asset.loadTracks(withMediaType: .video).first!
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            reader.add(output)
            reader.startReading()
            return (reader, output)
        }
        let (a, aOutput) = try await reader(with), (b, bOutput) = try await reader(without)
        var firstDifference = [Double?](repeating: nil, count: expected.count)
        while let first = aOutput.copyNextSampleBuffer(), let second = bOutput.copyNextSampleBuffer() {
            let time = first.presentationTimeStamp.seconds
            guard let index = expected.indices.first(where: { firstDifference[$0] == nil && time > expected[$0] - 0.1 && time < expected[$0] + 0.2 }),
                  let x = first.imageBuffer, let y = second.imageBuffer else { continue }
            CVPixelBufferLockBaseAddress(x, .readOnly); CVPixelBufferLockBaseAddress(y, .readOnly)
            let h = CVPixelBufferGetHeight(x), wx = CVPixelBufferGetBytesPerRow(x), wy = CVPixelBufferGetBytesPerRow(y), w = CVPixelBufferGetWidth(x)
            let px = CVPixelBufferGetBaseAddress(x)!.assumingMemoryBound(to: UInt8.self), py = CVPixelBufferGetBaseAddress(y)!.assumingMemoryBound(to: UInt8.self)
            var changed = 0
            for row in 0..<h { for column in 0..<w where abs(Int(px[row * wx + column * 4 + 1]) - Int(py[row * wy + column * 4 + 1])) > 10 { changed += 1 } }
            CVPixelBufferUnlockBaseAddress(x, .readOnly); CVPixelBufferUnlockBaseAddress(y, .readOnly)
            if changed > 8 { firstDifference[index] = time }
        }
        _ = (a, b)
        print("planned click   sound starts   effect first shows")
        for (index, moment) in expected.enumerated() {
            let onset = onsets.first { abs($0 - moment) < 0.15 }
            print(String(format: "%10.3f   %+9.1fms   %+12.1fms", moment, ((onset ?? .nan) - moment) * 1000, ((firstDifference[index] ?? .nan) - moment) * 1000))
        }
    }
}

extension ClickTiming {
    /// Plays the preview for real, as the editor does, and reports how far the picture falls behind the sound's clock.
    @MainActor static func live(folder: URL, seconds: Double, startAt: Double) async throws {
        let bundle = try RecordingBundle.load(from: folder)
        let session = try await PreviewSession.make(bundle: bundle, project: EditProject.open(bundle), previewWidth: 1280)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: nil)
        session.item.add(output)
        let player = AVPlayer(playerItem: session.item)
        player.volume = 0
        await player.seek(to: CMTime(seconds: startAt, preferredTimescale: 600))
        player.play()
        let begin = Date()
        var delivered: [(clock: Double, frame: Double)] = []
        while Date().timeIntervalSince(begin) < seconds {
            try await Task.sleep(nanoseconds: 4_000_000)
            let now = player.currentTime()
            if output.hasNewPixelBuffer(forItemTime: now) {
                var shown = CMTime.zero
                if output.copyPixelBuffer(forItemTime: now, itemTimeForDisplay: &shown) != nil { delivered.append((now.seconds, shown.seconds)) }
            }
        }
        player.pause()
        print(String(format: "%d frames in %.1f s of playback, %.0f a second", delivered.count, seconds, Double(delivered.count) / seconds))
        for step in stride(from: 0, to: delivered.count, by: max(1, delivered.count / 16)) {
            let d = delivered[step]
            print(String(format: "clock %7.3f  frame %7.3f  picture behind by %+6.0fms", d.clock, d.frame, (d.clock - d.frame) * 1000))
        }
        let lags = delivered.map { $0.clock - $0.frame }
        let gaps = zip(delivered, delivered.dropFirst()).map { $1.frame - $0.frame }
        print(String(format: "worst lag %.0fms, longest gap between frames %.0fms", (lags.max() ?? 0) * 1000, (gaps.max() ?? 0) * 1000))
    }
}
