import AVFoundation
import SoftcutCore
import CoreVideo
import Foundation

/// Recovers the camera from a finished video: for each moment, how far it was zoomed in and which part of the
/// raw screen recording was in the middle. It does this by finding where the raw frame for that moment lands in
/// the finished frame. Used to measure another app's automatic edit of a recording Softcut also has.
enum CameraTrace {
    struct Sample {
        let t: Double
        let scale: Double
        let centerX: Double
        let centerY: Double
        /// Average brightness difference (0...255) between the finished frame and the raw frame placed this way.
        let error: Double
    }

    /// A grey picture stored as rows of bytes.
    struct Gray {
        let width: Int
        let height: Int
        var pixels: [Float]

        func at(_ x: Double, _ y: Double) -> Float {
            // Bilinear, clamped to the edges.
            let fx = min(max(x, 0), Double(width - 1)), fy = min(max(y, 0), Double(height - 1))
            let x0 = Int(fx), y0 = Int(fy)
            let x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1)
            let ax = Float(fx - Double(x0)), ay = Float(fy - Double(y0))
            let top = pixels[y0 * width + x0] * (1 - ax) + pixels[y0 * width + x1] * ax
            let bottom = pixels[y1 * width + x0] * (1 - ax) + pixels[y1 * width + x1] * ax
            return top * (1 - ay) + bottom * ay
        }
    }

    /// Reads a video's frames in order, shrunk and in grey.
    final class FrameReader {
        private let reader: AVAssetReader
        private let output: AVAssetReaderTrackOutput
        private let shrink: Int
        private(set) var current: (t: Double, image: Gray)?
        private var pending: (t: Double, image: Gray)?

        init(url: URL, shrink: Int) async throws {
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw SoftcutError.noVideoTrack }
            reader = try AVAssetReader(asset: asset)
            output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            output.alwaysCopiesSampleData = false
            reader.add(output)
            guard reader.startReading() else { throw SoftcutError.invalidRecording(reader.error?.localizedDescription ?? "cannot read \(url.lastPathComponent)") }
            self.shrink = shrink
        }

        private func next() -> (t: Double, image: Gray)? {
            guard let buffer = output.copyNextSampleBuffer(), let pixels = CMSampleBufferGetImageBuffer(buffer) else { return nil }
            return (buffer.presentationTimeStamp.seconds, Self.gray(pixels, shrink: shrink))
        }

        /// The last frame shown at or before `time`.
        func frame(at time: Double) -> Gray? {
            if current == nil { current = pending ?? next(); pending = nil }
            while true {
                if pending == nil { pending = next() }
                guard let upcoming = pending, upcoming.t <= time + 0.0005 else { break }
                current = upcoming
                pending = nil
            }
            return current?.image
        }

        static func gray(_ buffer: CVPixelBuffer, shrink: Int) -> Gray {
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
            let w = width / shrink, h = height / shrink
            var out = [Float](repeating: 0, count: w * h)
            let area = Float(shrink * shrink)
            for y in 0..<h {
                for x in 0..<w {
                    var sum: Float = 0
                    for dy in 0..<shrink {
                        let row = base + (y * shrink + dy) * stride
                        for dx in 0..<shrink {
                            let p = row + (x * shrink + dx) * 4
                            sum += 0.114 * Float(p[0]) + 0.587 * Float(p[1]) + 0.299 * Float(p[2])
                        }
                    }
                    out[y * w + x] = sum / area
                }
            }
            return Gray(width: w, height: h, pixels: out)
        }
    }

    /// Where the screen sits in the finished frame when it is not zoomed, in the finished frame's pixels.
    struct Placement {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    /// Points inside the screen area, as fractions of it, kept away from its rounded corners.
    static let grid: [(Double, Double)] = {
        var points: [(Double, Double)] = []
        for j in 0..<36 { for i in 0..<56 { points.append((0.04 + 0.92 * (Double(i) + 0.5) / 56, 0.04 + 0.92 * (Double(j) + 0.5) / 36)) } }
        return points
    }()

    /// How different the finished frame is from the raw frame shown at `scale` around (cx, cy).
    /// The whole picture is magnified (screen and background together) about the camera center, which is given in
    /// the raw screen's own fractions and may lie beyond its edges. Parts of the frame that show background are skipped.
    static func error(finished: Gray, raw: Gray, placement: Placement, scale: Double, cx: Double, cy: Double) -> Double {
        var total: Float = 0
        var count = 0
        let midX = Double(finished.width) / 2, midY = Double(finished.height) / 2
        for (u, v) in frameGrid {
            let px = u * Double(finished.width), py = v * Double(finished.height)
            let ru = cx + (px - midX) / (scale * placement.width), rv = cy + (py - midY) / (scale * placement.height)
            // Stay clear of the screen's rounded edge, where background shows through.
            guard ru > 0.03, ru < 0.97, rv > 0.03, rv < 0.97 else { continue }
            total += abs(finished.at(px, py) - raw.at(ru * Double(raw.width), rv * Double(raw.height)))
            count += 1
        }
        // A placement that shows almost none of the screen cannot be judged.
        guard count > frameGrid.count / 4 else { return 255 }
        return Double(total) / Double(count)
    }

    /// Points across the whole finished frame, as fractions of it.
    static let frameGrid: [(Double, Double)] = {
        var points: [(Double, Double)] = []
        for j in 0..<40 { for i in 0..<60 { points.append((0.01 + 0.98 * (Double(i) + 0.5) / 60, 0.01 + 0.98 * (Double(j) + 0.5) / 40)) } }
        return points
    }()

    /// The raw-screen point at the middle of the frame when nothing is zoomed.
    static func restingCenter(_ placement: Placement, finished: Gray) -> (Double, Double) {
        ((Double(finished.width) / 2 - placement.x) / placement.width, (Double(finished.height) / 2 - placement.y) / placement.height)
    }

    /// Finds the unzoomed placement of the screen by trying sizes and positions, centered first.
    static func findPlacement(finished: Gray, raw: Gray) -> (Placement, Double) {
        let aspect = Double(raw.height) / Double(raw.width)
        var best = (Placement(x: 0, y: 0, width: Double(finished.width), height: Double(finished.width) * aspect), Double.infinity)
        func score(_ p: Placement) -> Double {
            var total: Float = 0
            for (u, v) in grid {
                total += abs(finished.at(p.x + u * p.width, p.y + v * p.height) - raw.at(u * Double(raw.width), v * Double(raw.height)))
            }
            return Double(total) / Double(grid.count)
        }
        for width in stride(from: Double(finished.width) * 0.6, through: Double(finished.width), by: 1) {
            let height = width * aspect
            guard height <= Double(finished.height) else { continue }
            let p = Placement(x: (Double(finished.width) - width) / 2, y: (Double(finished.height) - height) / 2, width: width, height: height)
            let e = score(p)
            if e < best.1 { best = (p, e) }
        }
        // Nudge position and size.
        var improved = true
        var step = 1.0
        while improved || step > 0.25 {
            improved = false
            for (dx, dy, dw) in [(step, 0.0, 0.0), (-step, 0, 0), (0, step, 0), (0, -step, 0), (0, 0, step), (0, 0, -step)] {
                let p = Placement(x: best.0.x + dx, y: best.0.y + dy, width: best.0.width + dw, height: (best.0.width + dw) * aspect)
                let e = score(p)
                if e < best.1 - 1e-6 { best = (p, e); improved = true }
            }
            if !improved { step /= 2 }
        }
        return best
    }

    /// The camera for one frame: a coarse search over zoom and position, then refined. Starts from the last answer.
    static func locate(finished: Gray, raw: Gray, placement: Placement, near previous: (Double, Double, Double)?) -> (scale: Double, cx: Double, cy: Double, error: Double) {
        func score(_ s: Double, _ x: Double, _ y: Double) -> Double {
            error(finished: finished, raw: raw, placement: placement, scale: s, cx: x, cy: y)
        }
        let rest = restingCenter(placement, finished: finished)
        var candidates: [(Double, Double, Double)] = [(1, rest.0, rest.1)]
        if let previous { candidates.append(previous) }
        for s in stride(from: 1.1, through: 2.6, by: 0.1) {
            for i in 0...10 { for j in 0...10 {
                candidates.append((s, -0.05 + 1.1 * Double(i) / 10, -0.05 + 1.1 * Double(j) / 10))
            } }
        }
        var best = (s: 1.0, x: rest.0, y: rest.1, e: Double.infinity)
        for c in candidates {
            let e = score(c.0, c.1, c.2)
            if e < best.e { best = (c.0, c.1, c.2, e) }
        }
        // Pattern search, halving the steps.
        var steps = (s: 0.05, p: 0.04)
        while steps.s > 0.002 {
            var improved = false
            for (ds, dx, dy) in [(steps.s, 0.0, 0.0), (-steps.s, 0, 0), (0, steps.p, 0), (0, -steps.p, 0), (0, 0, steps.p), (0, 0, -steps.p)] {
                let s = min(max(best.s + ds, 1), 3), x = best.x + dx, y = best.y + dy
                let e = score(s, x, y)
                if e < best.e - 1e-6 { best = (s, x, y, e); improved = true }
            }
            if !improved { steps = (steps.s / 2, steps.p / 2) }
        }
        return (best.s, best.x, best.y, best.e)
    }

    static func run(finishedURL: URL, rawURL: URL, fps: Double, duration: Double) async throws -> (Placement, [Sample]) {
        let finished = try await FrameReader(url: finishedURL, shrink: 1)
        let raw = try await FrameReader(url: rawURL, shrink: 2)
        // The first moment, before any zoom, shows where the screen sits.
        guard let firstFinished = finished.frame(at: 0.3), let firstRaw = raw.frame(at: 0.3) else { throw SoftcutError.noFramesCaptured }
        let (placement, placementError) = findPlacement(finished: firstFinished, raw: firstRaw)
        FileHandle.standardError.write(Data(String(format: "Screen sits at %.1f, %.1f, %.1f × %.1f (error %.1f)\n",
                                                    placement.x, placement.y, placement.width, placement.height, placementError).utf8))
        var samples: [Sample] = []
        var previous: (Double, Double, Double)?
        var t = 0.3
        while t < duration - 0.05 {
            guard let f = finished.frame(at: t), let r = raw.frame(at: t) else { break }
            let found = locate(finished: f, raw: r, placement: placement, near: previous)
            samples.append(Sample(t: t, scale: found.scale, centerX: found.cx, centerY: found.cy, error: found.error))
            previous = (found.scale, found.cx, found.cy)
            t += 1 / fps
        }
        return (placement, samples)
    }
}

/// Finds where another app drew the cursor in its finished video, given its camera for each frame (from
/// `CameraTrace`). The raw screen recording has no cursor, so the cursor is what differs between the finished frame
/// and the raw frame placed by that camera, near where the real mouse was.
enum CursorTrace {
    struct Sample {
        let t: Double
        /// Middle of the drawn cursor, in the raw screen's fractions.
        let x: Double
        let y: Double
        let pixels: Int
    }

    static func run(finishedURL: URL, rawURL: URL, cameras: [(t: Double, s: Double, x: Double, y: Double)], moves: [MouseSample]) async throws -> [Sample] {
        let finished = try await CameraTrace.FrameReader(url: finishedURL, shrink: 1)
        let raw = try await CameraTrace.FrameReader(url: rawURL, shrink: 2)
        guard let f0 = finished.frame(at: 0.3), let r0 = raw.frame(at: 0.3) else { throw SoftcutError.noFramesCaptured }
        let (placement, _) = CameraTrace.findPlacement(finished: f0, raw: r0)
        var samples: [Sample] = []
        var moveIndex = 0
        for (index, camera) in cameras.enumerated() {
            // While the camera moves the picture is blurred and differs everywhere; only still moments are judged.
            if index > 0 {
                let before = cameras[index - 1]
                if abs(before.s - camera.s) > 0.005 || abs(before.x - camera.x) > 0.002 || abs(before.y - camera.y) > 0.002 { continue }
            }
            guard let f = finished.frame(at: camera.t), let r = raw.frame(at: camera.t) else { break }
            while moveIndex < moves.count, moves[moveIndex].t <= camera.t { moveIndex += 1 }
            guard moveIndex > 0 else { continue }
            let mouse = moves[moveIndex - 1]
            let midX = Double(f.width) / 2, midY = Double(f.height) / 2
            let kx = camera.s * placement.width, ky = camera.s * placement.height
            let px = midX + (mouse.x - camera.x) * kx, py = midY + (mouse.y - camera.y) * ky
            // The drawn cursor can lag or lead the real one; look in a generous box around it.
            let reach = 110.0
            var sumX = 0.0, sumY = 0.0, weight = 0.0, count = 0
            var y = max(0, py - reach)
            while y < min(Double(f.height), py + reach) {
                var x = max(0, px - reach)
                while x < min(Double(f.width), px + reach) {
                    let ru = camera.x + (x - midX) / kx, rv = camera.y + (y - midY) / ky
                    if ru > 0.01, ru < 0.99, rv > 0.01, rv < 0.99 {
                        let d = Double(abs(f.at(x, y) - r.at(ru * Double(r.width), rv * Double(r.height))))
                        if d > 45 { sumX += ru * d; sumY += rv * d; weight += d; count += 1 }
                    }
                    x += 1
                }
                y += 1
            }
            guard count >= 20 else { continue }
            samples.append(Sample(t: camera.t, x: sumX / weight, y: sumY / weight, pixels: count))
        }
        return samples
    }
}
