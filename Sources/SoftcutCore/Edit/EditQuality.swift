import Foundation
import simd

/// Measures how watchable an automatic edit is, from the plan alone: are clicks in view when they happen, does the
/// camera move calmly, does the cursor land where it clicked. Used by tests and by `softcut-cli check`.
public struct EditQuality: Sendable, CustomStringConvertible {
    public struct Click: Sendable {
        public let time: Double
        /// How far from the middle of the picture the click is, as a share of the distance to its edge
        /// (0 is dead center, 1 is on the edge, above 1 out of view).
        public let offCenter: Double
        /// The closest to the middle it could be, given that the picture stops at the edges of the screen.
        public let bestOffCenter: Double
        public let zoomed: Bool
        /// Distance between the drawn cursor and the click, in display points.
        public let cursorMiss: Double
    }

    public let clicks: [Click]
    /// Separate camera movements while zoomed in.
    public let pans: Int
    /// Times the camera turned back on itself mid-move: a sign of wobble.
    public let reversals: Int
    /// Fastest the camera moves while zoomed, in display widths per second.
    public let fastestPan: Double
    /// Longest it takes, after a zoom begins, to be zoomed in fully.
    public let slowestZoomIn: Double
    public let zoomCount: Int
    public let zoomedSeconds: Double

    public var clicksInView: Int { clicks.filter { $0.offCenter <= 1 }.count }
    /// Clicks well inside the picture, or as close to the middle as the edge of the screen allows.
    public var clicksComfortable: Int { clicks.filter(\.isComfortable).count }
    public var worstCursorMiss: Double { clicks.map(\.cursorMiss).max() ?? 0 }

    public var description: String {
        var lines: [String] = []
        lines.append(String(format: "Zooms: %d, zoomed in for %.1fs", zoomCount, zoomedSeconds))
        lines.append("Clicks in view when they happen: \(clicksInView) of \(clicks.count) (well inside the picture: \(clicksComfortable))")
        lines.append(String(format: "Camera: %d pans while zoomed, %d wobbles, fastest %.2f screen widths/s", pans, reversals, fastestPan))
        lines.append(String(format: "Zooming in takes at most %.2fs", slowestZoomIn))
        lines.append(String(format: "Cursor lands within %.1f points of every click", worstCursorMiss))
        for click in clicks where !click.isComfortable {
            lines.append(String(format: "  click at %.2fs is %.0f%% of the way to the edge%@", click.time, click.offCenter * 100, click.offCenter > 1 ? " (out of view)" : ""))
        }
        return lines.joined(separator: "\n")
    }

    /// Measures the plan for the project's own recording.
    public static func measure(plan: EditPlan, bundle: RecordingBundle) -> EditQuality {
        let source = plan.sourcePlans[nil]!
        let crop = plan.settings.style.crop
        let width = bundle.manifest.displayWidth, height = bundle.manifest.displayHeight
        let zooms = source.zooms.filter { !$0.isDisabled && $0.presentation == .camera }
        let duration = bundle.manifest.duration

        var clicks: [Click] = []
        for press in AutoEditor.presses(bundle.input.clicks) where press.down <= duration - plan.settings.ignoreClicksAtEnd {
            let camera = source.camera(at: press.down, crop: crop)
            let halfWidth = crop.width / (2 * camera.scale), halfHeight = crop.height / (2 * camera.scale)
            let off = max(abs(press.x - camera.centerX) / halfWidth, abs(press.y - camera.centerY) / halfHeight)
            let bestX = min(max(press.x, crop.x + halfWidth), crop.x + crop.width - halfWidth)
            let bestY = min(max(press.y, crop.y + halfHeight), crop.y + crop.height - halfHeight)
            let best = max(abs(press.x - bestX) / halfWidth, abs(press.y - bestY) / halfHeight)
            let cursor = source.cursor(at: press.down)
            let miss = hypot((cursor.x - press.x) * width, (cursor.y - press.y) * height)
            clicks.append(Click(time: press.down, offCenter: off, bestOffCenter: best, zoomed: zooms.contains { press.down >= $0.start && press.down <= $0.end }, cursorMiss: miss))
        }

        // Camera motion while zoomed in, sampled at 60 per second.
        var pans = 0, reversals = 0
        var fastest = 0.0
        var moving = false
        var lastVelocity = SIMD2<Double>.zero
        let step = 1.0 / 60
        for zoom in zooms {
            var t = zoom.start + 0.6
            var previous = source.camera(at: t, crop: crop)
            while t < zoom.end - 0.1 {
                t += step
                let now = source.camera(at: t, crop: crop)
                let velocity = SIMD2(now.centerX - previous.centerX, now.centerY - previous.centerY) / step
                let speed = simd_length(velocity)
                fastest = max(fastest, speed)
                if speed > 0.02 {
                    if !moving { pans += 1 }
                    if moving, simd_dot(velocity, lastVelocity) < 0, simd_length(lastVelocity) > 0.02 { reversals += 1 }
                    moving = true
                    lastVelocity = velocity
                } else {
                    moving = false
                }
                previous = now
            }
        }

        var slowest = 0.0
        for zoom in zooms {
            var t = zoom.start
            while t < zoom.end, source.camera(at: t, crop: crop).scale < zoom.scale * 0.97 { t += 0.01 }
            slowest = max(slowest, t - zoom.start)
        }

        return EditQuality(clicks: clicks, pans: pans, reversals: reversals, fastestPan: fastest, slowestZoomIn: slowest,
                           zoomCount: zooms.count, zoomedSeconds: zooms.reduce(0) { $0 + $1.end - $1.start })
    }
}

public extension EditQuality.Click {
    var isComfortable: Bool { offCenter <= max(0.8, bestOffCenter + 0.05) }
}
