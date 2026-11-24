import Foundation
import simd

/// Turns a raw recording into an edit plan without any user input: smooth cursor,
/// zooms that follow clicks, and trimmed idle time.
public enum AutoEditor {
    static let trackRate = 120.0

    /// The automatic edit of a recording.
    public static func makePlan(for bundle: RecordingBundle, settings: EditSettings = EditSettings()) -> EditPlan {
        makePlan(for: bundle, project: .auto(for: bundle, settings: settings))
    }

    /// The plan for a project, which may have been changed by hand: its zooms and cuts are used as they are.
    /// Attached recordings are loaded from disk; use the `SourceSet` version to avoid doing that repeatedly.
    public static func makePlan(for bundle: RecordingBundle, project: EditProject) -> EditPlan {
        makePlan(sources: SourceSet.load(primary: bundle, project: project), project: project)
    }

    public static func makePlan(sources: SourceSet, project: EditProject) -> EditPlan {
        let settings = project.settings

        // How much bigger the whole video is than the screen in it. Zooming magnifies the whole picture, so this is how
        // far the camera must stay from the screen's edges for the zoomed screen to fill the video.
        let primary = sources.primary.manifest
        let layout = FrameRenderer.fullLayout(displayWidth: primary.displayWidth, displayHeight: primary.displayHeight, style: settings.style,
                                              hasCamera: FrameRenderer.usesCameraPanel(settings.style, hasWebcam: sources.hasWebcam))
        let coverage = layout.camera == nil && layout.content.width > 0
            ? SIMD2(layout.canvas.width / layout.content.width, layout.canvas.height / layout.content.height)
            : SIMD2(1.0, 1.0)

        func plan(for bundle: RecordingBundle, source: UUID?, zooms: [ZoomSegment], masks: [MaskRegion]) -> SourcePlan {
            let input = bundle.input
            let cursor = cursorTrack(moves: input.moves, clicks: input.clicks, duration: bundle.manifest.duration, smooth: settings.smoothCursor,
                                     aspect: bundle.manifest.displayHeight / max(1, bundle.manifest.displayWidth))
            // The text caret only steers the camera when typing zoom is on.
            let typing = settings.zoomOnTyping ? TypingContext(keys: input.keys, focus: input.focus) : TypingContext()
            // A magnifier leaves the camera where it is.
            let cameraZooms = zooms.filter { !$0.isDisabled && $0.presentation == .camera }
            let camera = cameraTrack(zooms: cameraZooms, clicks: input.clicks, moves: input.moves, cursor: cursor, typing: typing,
                                     duration: bundle.manifest.duration, settings: settings, coverage: coverage)
            var result = SourcePlan(zooms: zooms, clicks: input.clicks.filter { $0.down && $0.button == .left }, masks: masks,
                                    cursorTrack: cursor, cameraTrack: camera)
            result.captions = project.captions.filter { $0.source == source }.sorted { $0.start < $1.start }
            result.presses = presses(input.clicks)
            return result
        }

        var plans: [UUID?: SourcePlan] = [nil: plan(for: sources.primary, source: nil, zooms: project.zooms, masks: project.masks)]
        for attachment in project.attachments {
            if let bundle = sources.attached[attachment.id] {
                plans[attachment.id] = plan(for: bundle, source: attachment.id, zooms: attachment.zooms, masks: attachment.masks)
            }
        }

        // A clip whose recording is missing cannot be shown, so it is left out of the video.
        let playable = project.slices.filter { sources.bundle($0.sourceID) != nil }
        let timeMap = playable.isEmpty ? TimeMap.identity(duration: sources.primary.manifest.duration) : TimeMap(segments: playable)
        return EditPlan(settings: settings, timeMap: timeMap, audio: project.audio, sourcePlans: plans)
    }

    // MARK: Cursor

    /// The mouse counts as resting while it stays within this distance (a share of the screen's width, a few points)
    /// of where it is, for at least `restLength` seconds. Hand tremor stays inside it.
    static let restRadius = 0.003
    static let restLength = 0.1
    /// How much a movement's path is straightened out: wobbles shorter than this share of the movement are smoothed
    /// away, capped at `shapeLimit` of the screen so a long sweeping move keeps its general route.
    static let shapeSmoothing = 0.15
    static let shapeLimit = 0.04
    /// The cursor's speed along its path is softened over this long, so it gathers speed and slows down smoothly.
    static let paceSmoothing = 0.035

    /// The cursor as it appears in the video. Hand movement is split into rests and movements. While the mouse rests,
    /// the cursor holds perfectly still (on the exact spot of any click). Each movement from one rest to the next becomes
    /// one clean curve along the route the mouse took, with its wobbles straightened out, travelled with the same timing
    /// as the real movement but with speed that rises and falls smoothly. It starts when the mouse starts, lands where it
    /// stops, and never overshoots.
    static func cursorTrack(moves: [MouseSample], clicks: [ClickEvent] = [], duration: Double, smooth: Bool,
                            aspect: Double = 0.65) -> SampledTrack<SIMD2<Double>> {
        let count = max(2, Int(duration * trackRate) + 2)
        let dt = 1 / trackRate

        var raw = [SIMD2<Double>](repeating: SIMD2(0.5, 0.5), count: count)
        var moveIndex = 0
        var current = moves.first.map { SIMD2($0.x, $0.y) } ?? SIMD2(0.5, 0.5)
        for i in 0..<count {
            let t = Double(i) * dt
            while moveIndex < moves.count, moves[moveIndex].t <= t {
                current = SIMD2(moves[moveIndex].x, moves[moveIndex].y)
                moveIndex += 1
            }
            raw[i] = current
        }
        guard smooth else { return SampledTrack(rate: trackRate, samples: raw) }

        // Distances are measured on the screen as it looks, not in its stretched fractions.
        func distance(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { hypot(a.x - b.x, (a.y - b.y) * aspect) }

        // Rests: stretches where the mouse stays within a few points of where it is.
        let span = Int(restLength * trackRate / 2)
        var resting = [Bool](repeating: false, count: count)
        for i in 0..<count {
            var still = true
            for j in max(0, i - span)...min(count - 1, i + span) where distance(raw[j], raw[i]) > restRadius {
                still = false
                break
            }
            resting[i] = still
        }
        let minimumRest = Int(restLength * trackRate)
        var rests: [ClosedRange<Int>] = []
        var runStart: Int?
        for i in 0...count {
            if i < count, resting[i] { if runStart == nil { runStart = i }; continue }
            if let start = runStart {
                // The very start and end of the recording count as rests however short.
                if i - start >= minimumRest || start == 0 || i == count { rests.append(start...(i - 1)) }
                runStart = nil
            }
        }
        if rests.isEmpty { rests = [0...0, (count - 1)...(count - 1)] }
        if rests.first!.lowerBound != 0 { rests.insert(0...0, at: 0) }
        if rests.last!.upperBound != count - 1 { rests.append((count - 1)...(count - 1)) }

        // Every click is a point the cursor must pass exactly, even one made on the move without pausing.
        let downs = clicks.filter(\.down).sorted { $0.t < $1.t }
        for click in downs {
            let index = min(max(Int((click.t * trackRate).rounded()), 0), count - 1)
            if rests.contains(where: { $0.contains(index) }) { continue }
            rests.append(index...index)
        }
        rests.sort { $0.lowerBound < $1.lowerBound }

        // Where the cursor holds during each rest: on the click, if there is one, otherwise the middle of the wobble.
        let holds: [SIMD2<Double>] = rests.map { rest in
            let from = Double(rest.lowerBound) * dt - 0.05, to = Double(rest.upperBound) * dt + 0.05
            if let click = downs.first(where: { $0.t >= from && $0.t <= to }) { return SIMD2(click.x, click.y) }
            let xs = raw[rest].map(\.x).sorted(), ys = raw[rest].map(\.y).sorted()
            return SIMD2(xs[xs.count / 2], ys[ys.count / 2])
        }

        var out = raw
        for (index, rest) in rests.enumerated() {
            for i in rest { out[i] = holds[index] }
        }

        for index in 0..<(rests.count - 1) {
            let first = rests[index].upperBound, last = rests[index + 1].lowerBound
            guard last - first > 1 else { continue }
            let a = holds[index], b = holds[index + 1]

            // The route: the raw path, pinned to the two rests, measured along its length.
            var route = [a]
            for i in (first + 1)..<last { route.append(raw[i]) }
            route.append(b)
            var along = [0.0]
            for k in 1..<route.count { along.append(along[k - 1] + distance(route[k - 1], route[k])) }
            let length = along.last!
            if length < 1e-5 {
                for i in first...last { out[i] = a }
                continue
            }

            // Shape: the route resampled evenly along its length, then wobbles shorter than a share of it smoothed away,
            // keeping both ends exactly in place.
            let pointCount = 64
            var shape: [SIMD2<Double>] = []
            var cursor = 0
            for k in 0...pointCount {
                let target = length * Double(k) / Double(pointCount)
                while cursor < along.count - 2, along[cursor + 1] < target { cursor += 1 }
                let segment = along[cursor + 1] - along[cursor]
                let f = segment > 0 ? (target - along[cursor]) / segment : 0
                shape.append(route[cursor] + (route[cursor + 1] - route[cursor]) * f)
            }
            let sigma = min(shapeSmoothing, shapeLimit / length) * Double(pointCount)
            if sigma > 0.5 {
                let width = Int(3 * sigma)
                var smoothed = shape
                for k in 0...pointCount {
                    var sum = SIMD2<Double>.zero, weight = 0.0
                    for j in (k - width)...(k + width) {
                        let w = exp(-Double((j - k) * (j - k)) / (2 * sigma * sigma))
                        sum += shape[min(max(j, 0), pointCount)] * w
                        weight += w
                    }
                    smoothed[k] = sum / weight
                }
                let startError = smoothed[0] - a, endError = smoothed[pointCount] - b
                for k in 0...pointCount {
                    let f = Double(k) / Double(pointCount)
                    smoothed[k] -= startError * (1 - f) + endError * f
                }
                shape = smoothed
            }

            // Pace: how far along the route the real mouse was at each moment, softened so the speed rises and falls
            // smoothly, still starting at 0 and reaching 1 exactly at the next rest.
            var progress = [Double](repeating: 0, count: last - first + 1)
            for i in first...last {
                let k = i - first
                progress[k] = k == 0 ? 0 : (i == last ? 1 : along[min(k, along.count - 2)] / length)
            }
            let paceWidth = Int(3 * paceSmoothing * trackRate)
            let paceSigma = paceSmoothing * trackRate
            var paced = progress
            for k in 0..<progress.count {
                var sum = 0.0, weight = 0.0
                for j in (k - paceWidth)...(k + paceWidth) {
                    let w = exp(-Double((j - k) * (j - k)) / (2 * paceSigma * paceSigma))
                    sum += (j < 0 ? 0 : (j >= progress.count ? 1 : progress[j])) * w
                    weight += w
                }
                paced[k] = sum / weight
            }
            // Pinned to the ends and never going backwards.
            let low = paced.first!, high = paced.last!
            var furthest = 0.0
            for k in 0..<paced.count {
                let p = high > low ? (paced[k] - low) / (high - low) : Double(k) / Double(max(1, paced.count - 1))
                furthest = max(furthest, min(max(p, 0), 1))
                paced[k] = furthest
            }

            for i in first...last {
                let position = paced[i - first] * Double(pointCount)
                let k = min(Int(position), pointCount - 1)
                out[i] = shape[k] + (shape[k + 1] - shape[k]) * (position - Double(k))
            }
        }
        return SampledTrack(rate: trackRate, samples: out)
    }

    // MARK: Zoom

    /// A left click: where and when the button went down, and when it came back up.
    struct Press {
        let x: Double
        let y: Double
        let down: Double
        let up: Double
    }

    /// Left clicks on the recorded display, each paired with its release.
    static func presses(_ clicks: [ClickEvent]) -> [Press] {
        let sorted = clicks.sorted { $0.t < $1.t }
        var result: [Press] = []
        for (index, click) in sorted.enumerated() where click.down && click.button == .left {
            guard (0...1).contains(click.x), (0...1).contains(click.y) else { continue }
            let release = sorted[(index + 1)...].first { !$0.down && $0.button == click.button }
            result.append(Press(x: click.x, y: click.y, down: click.t, up: max(click.t, release?.t ?? click.t + 0.1)))
        }
        return result
    }

    /// Zooms for a recording. Each click asks for a zoom from shortly before the button goes down until a while
    /// after it comes up; zooms that nearly touch become one, inside which the camera moves from click to click.
    static func planZooms(clicks: [ClickEvent], keys: [KeyEvent] = [], focus: [FocusSample] = [],
                          moves: [MouseSample] = [], duration: Double, settings: EditSettings) -> [ZoomSegment] {
        let usable = presses(clicks).filter { $0.down <= duration - settings.ignoreClicksAtEnd }
        var candidates: [ZoomSegment] = usable.map { press in
            ZoomSegment(start: max(0, press.down - settings.clickZoomLead),
                        end: min(duration, press.up + settings.clickZoomHold),
                        focusX: press.x, focusY: press.y, focusTime: press.down, scale: settings.zoomScale)
        }

        if settings.zoomOnTyping {
            let typing = TypingContext(keys: keys, focus: focus)
            for burst in typingBursts(keys: keys, settings: settings) {
                // Aim at the caret when it is known; otherwise at the mouse, which is usually
                // still where the text field was clicked.
                let aim = typing.caret(at: burst.start + 0.3)
                    ?? lastMousePosition(in: moves, at: burst.start)
                    ?? SIMD2(0.5, 0.5)
                candidates.append(ZoomSegment(start: max(0, burst.start - settings.typingLeadIn),
                                              end: min(duration, burst.end + settings.typingHold),
                                              focusX: aim.x, focusY: aim.y, focusTime: burst.start,
                                              scale: settings.typingZoomScale))
            }
        }

        var segments: [ZoomSegment] = []
        for segment in candidates.sorted(by: { $0.start < $1.start }) {
            if var previous = segments.last, segment.start - previous.end < settings.zoomMergeGap {
                previous.end = max(previous.end, segment.end)
                previous.scale = max(previous.scale, segment.scale)
                segments[segments.count - 1] = previous
            } else {
                segments.append(segment)
            }
        }
        return segments
    }

    /// Stretches of typing: key presses with short gaps between them. Shortcuts do not count,
    /// and neither does a lone key press.
    static func typingBursts(keys: [KeyEvent], settings: EditSettings) -> [(start: Double, end: Double, count: Int)] {
        var bursts: [(start: Double, end: Double, count: Int)] = []
        for time in keys.filter({ !$0.shortcut }).map(\.t).sorted() {
            if let last = bursts.last, time - last.end <= settings.typingGap {
                bursts[bursts.count - 1].end = time
                bursts[bursts.count - 1].count += 1
            } else {
                bursts.append((time, time, 1))
            }
        }
        return bursts.filter { $0.count >= settings.typingMinKeys }
    }

    private static func lastMousePosition(in moves: [MouseSample], at time: Double) -> SIMD2<Double>? {
        guard let move = moves.last(where: { $0.t <= time }) else { return nil }
        return SIMD2(move.x, move.y)
    }

    // MARK: Camera

    /// A group of clicks that fit in view together, and where the camera points to show them.
    struct ClickGroup: Equatable {
        let firstDown: Double
        let lastUp: Double
        let center: SIMD2<Double>
        /// Where its first click is.
        let firstPoint: SIMD2<Double>
    }

    /// Share of the visible area that the clicks in one group may spread over.
    static let groupSpread = 0.5
    /// A pause longer than this between clicks starts a new group, even in the same place.
    static let groupPause = 3.0
    /// When the mouse strays, the camera goes to the next group of clicks if it begins within this many seconds.
    static let groupLookAhead = 1.5
    /// While typing, the text caret is kept within this share of the picture.
    static let caretMargin = 0.55

    /// The groups of clicks in a zoom, in order. Each new click joins the group before it if it comes within a few
    /// seconds and all of them still fit in half of the picture; otherwise it starts a new group. A fixed zoom, or one without clicks, has one group at its
    /// focus point.
    static func clickGroups(for zoom: ZoomSegment, presses: [Press], crop: CropRect) -> [ClickGroup] {
        let halfWidth = crop.width / (2 * zoom.scale)
        let halfHeight = crop.height / (2 * zoom.scale)
        func inside(_ point: SIMD2<Double>) -> SIMD2<Double> {
            SIMD2(min(max(point.x, crop.x + halfWidth), crop.x + crop.width - halfWidth),
                  min(max(point.y, crop.y + halfHeight), crop.y + crop.height - halfHeight))
        }
        let mine = presses.filter { $0.down >= zoom.start && $0.down <= zoom.end }
        guard zoom.follow == .auto, !mine.isEmpty else {
            let focus = SIMD2(zoom.focusX, zoom.focusY)
            return [ClickGroup(firstDown: zoom.start, lastUp: zoom.end, center: inside(focus), firstPoint: focus)]
        }
        var groups: [[Press]] = []
        for press in mine {
            if let group = groups.last, press.down - group.last!.up <= groupPause {
                let xs = group.map(\.x) + [press.x], ys = group.map(\.y) + [press.y]
                if xs.max()! - xs.min()! <= 2 * halfWidth * groupSpread, ys.max()! - ys.min()! <= 2 * halfHeight * groupSpread {
                    groups[groups.count - 1].append(press)
                    continue
                }
            }
            groups.append([press])
        }
        return groups.map { group in
            let xs = group.map(\.x), ys = group.map(\.y)
            return ClickGroup(firstDown: group[0].down, lastUp: group.last!.up,
                              center: inside(SIMD2((xs.min()! + xs.max()!) / 2, (ys.min()! + ys.max()!) / 2)),
                              firstPoint: SIMD2(group[0].x, group[0].y))
        }
    }

    /// How long the camera takes to zoom in or out, and to move across the screen while zoomed. Every move uses
    /// the same easing curve, so they all feel alike.
    static let zoomDuration = 0.7
    static let panDuration = 0.6
    /// An instant zoom is a quick cut in and out.
    static let instantDuration = 0.12
    /// While zoomed, the camera stays put until the mouse leaves this share of the picture around its middle,
    /// then re-centers on where the mouse is going.
    static let deadZone = 0.6
    /// A click this far from the middle (as a share of the way to the edge) gets the camera moving before it happens.
    static let clickZone = 0.5
    /// How long before such a click the camera sets off. The move takes 0.6 s, so the picture is still before the click lands.
    static let groupLead = 0.75

    /// Where the mouse comes to rest after `time`: the first moment it has been still for a short while, looking at
    /// most `limit` seconds ahead.
    static func restingPoint(after time: Double, moves: [MouseSample], limit: Double = 0.8) -> SIMD2<Double>? {
        var low = 0, high = moves.count
        while low < high { let mid = (low + high) / 2; if moves[mid].t < time { low = mid + 1 } else { high = mid } }
        guard low < moves.count else { return moves.last.map { SIMD2($0.x, $0.y) } }
        var anchor = moves[max(0, low - 1)]
        var index = low
        while index < moves.count, moves[index].t <= time + limit {
            let move = moves[index]
            if hypot(move.x - anchor.x, move.y - anchor.y) > 0.004 { anchor = move }
            else if move.t - anchor.t >= 0.15 { return SIMD2(anchor.x, anchor.y) }
            index += 1
        }
        return SIMD2(anchor.x, anchor.y)
    }

    /// Where the camera is: how far it is zoomed in and which point of the screen is in the middle.
    struct CameraPose: Equatable {
        var scale: Double
        var center: SIMD2<Double>
    }

    /// The steady curve (easing off): it gathers speed gently, travels at a steady pace through the middle, and
    /// settles gently. Nothing overshoots, so nothing bounces.
    static func ease(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        let ramp = 0.3
        let top = 1 / (1 - ramp)
        if t < ramp { return top * t * t / (2 * ramp) }
        if t > 1 - ramp { return 1 - top * (1 - t) * (1 - t) / (2 * ramp) }
        return top * (t - ramp / 2)
    }

    /// The eased curve (easing on): starts and ends softly, with no sudden change of speed anywhere, fastest in the middle.
    static func easeInOut(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * t * (t * (t * 6 - 15) + 10)
    }

    /// The pose part way (`progress`, 0 to 1, already eased) from `a` to `b`. Zooming happens about the one point of the
    /// screen that is in the same place in both views, so it stays put on screen while everything else grows or
    /// shrinks around it, and the zoom level changes at a steady rate to the eye (geometrically). With no change of
    /// zoom, the camera simply slides.
    static func blend(_ a: CameraPose, _ b: CameraPose, _ progress: Double) -> CameraPose {
        let p = min(max(progress, 0), 1)
        guard abs(a.scale - b.scale) > 1e-6 else {
            return CameraPose(scale: a.scale, center: a.center + (b.center - a.center) * p)
        }
        let scale = a.scale * pow(b.scale / a.scale, p)
        let still = (a.center * a.scale - b.center * b.scale) / (a.scale - b.scale)
        return CameraPose(scale: scale, center: still - (still - a.center) * (a.scale / scale))
    }

    /// Plays out the camera over the whole recording. A zoom eases in on its first group of clicks; after that the
    /// camera holds still while the mouse stays near the middle of the picture, sets off for the next group of clicks
    /// just in time to be there for the first of them, and follows the mouse to where it comes to rest when it strays
    /// out without clicking. At the end of the zoom it eases back out.
    static func cameraTrack(zooms: [ZoomSegment], clicks: [ClickEvent] = [], moves: [MouseSample] = [], cursor: SampledTrack<SIMD2<Double>>,
                            typing: TypingContext = TypingContext(), duration: Double, settings: EditSettings,
                            coverage: SIMD2<Double> = SIMD2(1, 1)) -> SampledTrack<SIMD3<Double>> {
        let count = max(2, Int(duration * trackRate) + 2)
        let dt = 1 / trackRate
        let crop = settings.style.crop
        let idle = CameraPose(scale: 1, center: crop.center)
        let allPresses = presses(clicks)
        let plans = zooms.map { (zoom: $0, groups: clickGroups(for: $0, presses: allPresses, crop: crop)) }
        let sortedMoves = moves.sorted { $0.t < $1.t }

        var out = [SIMD3<Double>](repeating: SIMD3(1, idle.center.x, idle.center.y), count: count)
        var planIndex = 0
        var activeZoom: UUID?
        var target = idle.center
        var groupIndex = 0
        var holdUntil = 0.0
        var moveIndex = 0
        // The move under way: from where, to where, starting when, for how long.
        var move = (from: idle, to: idle, start: 0.0, length: 1.0)
        var pose = idle

        for i in 0..<count {
            let t = Double(i) * dt
            while planIndex < plans.count, plans[planIndex].zoom.end < t { planIndex += 1 }
            let current = planIndex < plans.count && plans[planIndex].zoom.start <= t ? plans[planIndex] : nil
            let moving = t < move.start + move.length

            var goal = idle
            if let current {
                let zoom = current.zoom
                let halfWidth = crop.width / (2 * zoom.scale)
                let halfHeight = crop.height / (2 * zoom.scale)
                // The whole video is a little wider than the screen in it (the padding). Keep the zoomed screen covering
                // all of it, so no strip of background shows beside the screen's edge.
                func inside(_ point: SIMD2<Double>) -> SIMD2<Double> {
                    func fit(_ value: Double, _ low: Double, _ size: Double, _ half: Double) -> Double {
                        let lower = low + half, upper = low + size - half
                        return lower > upper ? low + size / 2 : min(max(value, lower), upper)
                    }
                    return SIMD2(fit(point.x, crop.x, crop.width, halfWidth * coverage.x),
                                 fit(point.y, crop.y, crop.height, halfHeight * coverage.y))
                }
                if activeZoom != zoom.id {
                    activeZoom = zoom.id
                    // Where the zoom starts: its first clicks, or the point chosen for it by hand.
                    let focus = SIMD2(zoom.focusX, zoom.focusY)
                    target = simd_length(focus - current.groups[0].firstPoint) < 1e-6 ? current.groups[0].center : focus
                    groupIndex = 0
                }
                if zoom.follow == .auto {
                    while moveIndex < sortedMoves.count, sortedMoves[moveIndex].t <= t { moveIndex += 1 }
                    let mouse = moveIndex > 0 ? SIMD2(sortedMoves[moveIndex - 1].x, sortedMoves[moveIndex - 1].y) : cursor.samples[min(i, cursor.samples.count - 1)]
                    let caret = typing.caret(at: t)
                    let watched = caret ?? mouse
                    let zone = caret == nil ? deadZone : caretMargin
                    // A group of clicks coming up that is not comfortably in view: set off for it just in time.
                    if caret == nil, let next = current.groups.indices.first(where: { $0 > groupIndex && current.groups[$0].firstDown >= t }),
                       current.groups[next].firstDown - t <= groupLead {
                        groupIndex = next
                        let first = current.groups[next].firstPoint
                        if abs(first.x - target.x) > halfWidth * clickZone || abs(first.y - target.y) > halfHeight * clickZone {
                            target = current.groups[next].center
                            // The mouse is usually still on its way; do not turn back for it before the click.
                            holdUntil = current.groups[next].firstDown
                        }
                    } else if !moving, t > holdUntil, t > zoom.start + zoomDuration,
                              abs(watched.x - target.x) > halfWidth * zone || abs(watched.y - target.y) > halfHeight * zone {
                        // Strayed without clicking: go where the mouse (or the text being typed) is headed. Only once the
                        // camera is still, so one move is never cut short by the next.
                        target = caret ?? restingPoint(after: t, moves: sortedMoves) ?? watched
                    }
                    target = inside(target)
                } else {
                    target = inside(SIMD2(zoom.focusX, zoom.focusY))
                }
                goal = CameraPose(scale: zoom.scale, center: target)
            } else {
                activeZoom = nil
            }

            // A new place to be: start a move there from wherever the camera is now.
            if simd_length(goal.center - move.to.center) > 1e-4 || abs(goal.scale - move.to.scale) > 1e-4 {
                let zooming = abs(goal.scale - pose.scale) > 0.01
                let instant = zooms.contains { $0.instant && (abs(t - $0.start) < 0.05 || abs(t - $0.end) < 0.05) }
                move = (pose, goal, t, instant ? instantDuration : (zooming ? zoomDuration : panDuration))
            }
            let progress = (t - move.start) / move.length
            pose = blend(move.from, move.to, settings.zoomEasing ? easeInOut(progress) : ease(progress))
            out[i] = SIMD3(pose.scale, pose.center.x, pose.center.y)
        }
        return SampledTrack(rate: trackRate, samples: out)
    }

    // MARK: Time

    /// Typing shorter than this is left at normal speed: speeding it up would only flicker.
    static let typingSpeedMinimum = 1.0

    static func planTime(input: InputLog, duration: Double, hasAudio: Bool, hasVoice: Bool = false, typingTracked: Bool = true,
                         settings: EditSettings) -> TimeMap {
        guard duration > 0 else { return .identity(duration: 0) }
        let keptEnd = max(1, duration - settings.trimTail)
        let activity = activityTimes(input).filter { $0 <= keptEnd }
        var start = 0.0
        var end = min(duration, keptEnd)

        // Both trimming and speeding up decide that nothing is happening from mouse activity alone,
        // which is only safe when typing was being recorded too.
        let canJudgeIdle = !hasAudio && typingTracked
        if settings.trimIdleEnds, canJudgeIdle, let firstActive = activity.first, let lastActive = activity.last {
            if firstActive > settings.trimThreshold { start = firstActive - settings.trimMargin }
            if keptEnd - lastActive > settings.trimThreshold { end = lastActive + settings.trimMargin }
            if end - start < 1 { start = 0; end = keptEnd }
        }

        // Stretches that play faster: typing, and (if turned on) stretches where nothing happens.
        var fast: [(start: Double, end: Double, speed: Double)] = []
        if settings.speedUpTyping, typingTracked, !hasVoice {
            for burst in typingBursts(keys: input.keys, settings: settings) where burst.end - burst.start >= typingSpeedMinimum {
                // The first key or two at normal speed, so the viewer sees typing begin.
                fast.append((burst.start + 0.15, burst.end + 0.15, settings.typingSpeed))
            }
        }
        if settings.speedUpIdle, canJudgeIdle, !activity.isEmpty {
            let inside = activity.filter { $0 >= start && $0 <= end }
            for (a, b) in zip(inside, inside.dropFirst()) where b - a > settings.idleThreshold {
                fast.append((a + 0.5, b - 0.5, settings.idleSpeed))
            }
        }

        var segments: [TimeSegment] = []
        var cursor = start
        for range in fast.sorted(by: { $0.start < $1.start }) {
            let from = max(range.start, cursor), to = min(range.end, end)
            guard to - from >= 0.3 else { continue }
            if from > cursor { segments.append(TimeSegment(sourceStart: cursor, sourceEnd: from)) }
            segments.append(TimeSegment(sourceStart: from, sourceEnd: to, speed: range.speed))
            cursor = to
        }
        if end > cursor { segments.append(TimeSegment(sourceStart: cursor, sourceEnd: end)) }
        if segments.isEmpty { segments = [TimeSegment(sourceStart: start, sourceEnd: end)] }
        return TimeMap(segments: segments)
    }

    /// Times at which the user did something with the mouse.
    static func activityTimes(_ input: InputLog) -> [Double] {
        // Typing counts as activity: a quiet mouse during typing is not an idle stretch.
        var times: [Double] = input.clicks.map(\.t) + input.scrolls.map(\.t) + input.keys.map(\.t)
        var previous: MouseSample?
        for move in input.moves {
            if let previous, abs(move.x - previous.x) + abs(move.y - previous.y) > 0.002 {
                times.append(move.t)
            }
            previous = move
        }
        return times.sorted()
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
