import XCTest
@testable import GlideCore

final class TimeMapTests: XCTestCase {
    func testMapsOutputTimeThroughSpeedSegments() {
        let map = TimeMap(segments: [
            TimeSegment(sourceStart: 0, sourceEnd: 2),
            TimeSegment(sourceStart: 2, sourceEnd: 6, speed: 4),
            TimeSegment(sourceStart: 6, sourceEnd: 8),
        ])
        XCTAssertEqual(map.outputDuration, 5, accuracy: 1e-9)
        XCTAssertEqual(map.sourceTime(forOutput: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(map.sourceTime(forOutput: 1.5), 1.5, accuracy: 1e-9)
        XCTAssertEqual(map.sourceTime(forOutput: 2.5), 4, accuracy: 1e-9)
        // Output 3.0 is where the third segment starts (2s + 1s of the sped-up middle), so 4.5 is 1.5s in.
        XCTAssertEqual(map.sourceTime(forOutput: 4.5), 7.5, accuracy: 1e-9)
        XCTAssertEqual(map.sourceTime(forOutput: 99), 8, accuracy: 1e-9)
    }

    func testDropsEmptySegments() {
        let map = TimeMap(segments: [TimeSegment(sourceStart: 1, sourceEnd: 1), TimeSegment(sourceStart: 1, sourceEnd: 3)])
        XCTAssertEqual(map.segments.count, 1)
        XCTAssertEqual(map.outputDuration, 2, accuracy: 1e-9)
    }
}

final class ZoomPlanTests: XCTestCase {
    /// A press: the button goes down at `t` and comes up a tenth of a second later.
    private func press(_ t: Double, x: Double = 0.5, y: Double = 0.5, hold: Double = 0.1, button: MouseButton = .left) -> [ClickEvent] {
        [ClickEvent(t: t, x: x, y: y, button: button, down: true), ClickEvent(t: t + hold, x: x, y: y, button: button, down: false)]
    }

    func testAZoomRunsFromJustBeforeThePressToAWhileAfterTheRelease() {
        let zooms = AutoEditor.planZooms(clicks: press(7, hold: 0.12), duration: 20, settings: EditSettings())
        XCTAssertEqual(zooms.count, 1)
        XCTAssertEqual(zooms[0].start, 6.15, accuracy: 1e-9)
        XCTAssertEqual(zooms[0].end, 7.12 + 2.5, accuracy: 1e-9)
        XCTAssertEqual(zooms[0].scale, 2, accuracy: 1e-9)
    }

    func testAHeldPressKeepsTheZoomUntilItIsLetGo() {
        // Dragging something: the zoom lasts until the drag ends, then the usual time after.
        let zooms = AutoEditor.planZooms(clicks: press(3, hold: 1.9), duration: 20, settings: EditSettings())
        XCTAssertEqual(zooms[0].end, 3 + 1.9 + 2.5, accuracy: 1e-9)
    }

    func testClicksAFewSecondsApartShareOneZoomAndTheCameraStaysIn() {
        // 4.6 s between presses: the zooms would be 1.7 s apart, too close to go out and back in.
        let zooms = AutoEditor.planZooms(clicks: press(10) + press(14.6), duration: 30, settings: EditSettings())
        XCTAssertEqual(zooms.count, 1)
        XCTAssertEqual(zooms[0].start, 9.15, accuracy: 1e-9)
        XCTAssertEqual(zooms[0].end, 14.7 + 2.5, accuracy: 1e-9)
    }

    func testClicksFarApartGetTheirOwnZooms() {
        let zooms = AutoEditor.planZooms(clicks: press(10) + press(16.5), duration: 30, settings: EditSettings())
        XCTAssertEqual(zooms.count, 2)
    }

    func testRightClicksMouseUpsAndClicksOffTheDisplayAreIgnored() {
        let clicks = press(2, button: .right) + [ClickEvent(t: 4, x: 0.5, y: 0.5, down: false)] + press(6, x: 1.4)
        XCTAssertTrue(AutoEditor.planZooms(clicks: clicks, duration: 20, settings: EditSettings()).isEmpty)
    }

    func testTheClickThatStopsTheRecordingIsIgnored() {
        let zooms = AutoEditor.planZooms(clicks: press(3) + press(9.8), duration: 10, settings: EditSettings())
        XCTAssertEqual(zooms.count, 1)
        XCTAssertEqual(zooms[0].start, 2.15, accuracy: 1e-9)
    }

    func testZoomStaysInsideRecording() {
        let zooms = AutoEditor.planZooms(clicks: press(0.1) + press(8), duration: 10, settings: EditSettings())
        XCTAssertEqual(zooms.first?.start, 0)
        XCTAssertEqual(zooms.last?.end ?? 99, 10, accuracy: 1e-9)
    }
}

/// The automatic zooms must come out the way Screen Studio's do for the same clicks. They end at the same moment;
/// they start 0.55 s earlier, so Glide's eased zoom has finished arriving before the click lands.
final class ScreenStudioParityTests: XCTestCase {
    func testZoomsMatchScreenStudioOnRealRecordings() {
        for recording in ScreenStudioReference.recordings {
            var settings = EditSettings()
            settings.zoomOnTyping = false
            let zooms = AutoEditor.planZooms(clicks: recording.clicks, duration: recording.duration, settings: settings)
            XCTAssertEqual(zooms.count, recording.zooms.count, recording.name)
            for (ours, theirs) in zip(zooms, recording.zooms) {
                XCTAssertEqual(ours.start, max(0, theirs.start - 0.55), accuracy: 0.02, "\(recording.name) start")
                XCTAssertEqual(ours.end, theirs.end, accuracy: 0.02, "\(recording.name) end")
                XCTAssertEqual(ours.scale, 2, accuracy: 1e-9)
            }
        }
    }

    func testEveryClickInARealRecordingIsInViewWhenItHappens() {
        // The long recording: 37 clicks over a minute, mostly on the right of the screen.
        let recording = ScreenStudioReference.recordings.max { $0.clicks.count < $1.clicks.count }!
        var moves: [MouseSample] = []
        // Mouse moves are not kept in the fixture; the cursor goes straight from click to click.
        for click in recording.clicks where click.down { moves.append(MouseSample(t: click.t - 0.4, x: click.x, y: click.y)) }
        var settings = EditSettings()
        settings.zoomOnTyping = false
        let zooms = AutoEditor.planZooms(clicks: recording.clicks, duration: recording.duration, settings: settings)
        let cursor = AutoEditor.cursorTrack(moves: moves, duration: recording.duration, smooth: true)
        let camera = AutoEditor.cameraTrack(zooms: zooms, clicks: recording.clicks, cursor: cursor, duration: recording.duration, settings: settings)
        let plan = EditPlan(settings: settings, timeMap: .identity(duration: recording.duration), zooms: zooms,
                            clicks: recording.clicks.filter(\.down), cursorTrack: cursor, cameraTrack: camera)
        for click in AutoEditor.presses(recording.clicks) where click.down < recording.duration - 0.5 {
            let state = plan.camera(at: click.down)
            let half = SIMD2(0.5 / state.scale, 0.5 / state.scale)
            // As close to the middle as the edge of the screen allows.
            let best = SIMD2(min(max(click.x, half.x), 1 - half.x), min(max(click.y, half.y), 1 - half.y))
            let offset = max(abs(click.x - state.centerX) / half.x, abs(click.y - state.centerY) / half.y)
            let bestOffset = max(abs(click.x - best.x) / half.x, abs(click.y - best.y) / half.y)
            XCTAssertLessThanOrEqual(offset, max(0.8, bestOffset + 0.05), "click at \(click.down)")
        }
    }
}

final class CameraTests: XCTestCase {
    private func plan(zooms: [ZoomSegment], moves: [MouseSample], duration: Double = 10) -> EditPlan {
        let settings = EditSettings()
        let cursor = AutoEditor.cursorTrack(moves: moves, duration: duration, smooth: true)
        let camera = AutoEditor.cameraTrack(zooms: zooms, cursor: cursor, duration: duration, settings: settings)
        return EditPlan(settings: settings, timeMap: .identity(duration: duration), zooms: zooms, clicks: [],
                        cursorTrack: cursor, cameraTrack: camera)
    }

    func testZoomsInHoldsAndReturns() {
        let zoom = ZoomSegment(start: 2, end: 5, focusX: 0.3, focusY: 0.4, focusTime: 3)
        let plan = plan(zooms: [zoom], moves: [MouseSample(t: 0, x: 0.3, y: 0.4)])
        XCTAssertLessThan(plan.camera(at: 1).scale, 1.01)
        let held = plan.camera(at: 4.5)
        XCTAssertGreaterThan(held.scale, 1.9)
        XCTAssertEqual(held.centerX, 0.3, accuracy: 0.02)
        XCTAssertEqual(held.centerY, 0.4, accuracy: 0.02)
        XCTAssertLessThan(plan.camera(at: 9.5).scale, 1.05)
    }

    func testVisibleAreaNeverLeavesTheScreen() {
        // Focus in the corner: the camera must stop at the edge instead of showing empty space.
        let zoom = ZoomSegment(start: 1, end: 6, focusX: 0.02, focusY: 0.98, focusTime: 2)
        let plan = plan(zooms: [zoom], moves: [MouseSample(t: 0, x: 0.02, y: 0.98)])
        for step in 0..<100 {
            let state = plan.camera(at: Double(step) / 10)
            let half = 0.5 / state.scale
            XCTAssertGreaterThanOrEqual(state.centerX - half, -1e-9)
            XCTAssertLessThanOrEqual(state.centerX + half, 1 + 1e-9)
            XCTAssertGreaterThanOrEqual(state.centerY - half, -1e-9)
            XCTAssertLessThanOrEqual(state.centerY + half, 1 + 1e-9)
        }
    }

    func testSmallCursorMovesDoNotMoveTheCamera() {
        let zoom = ZoomSegment(start: 1, end: 9, focusX: 0.5, focusY: 0.5, focusTime: 2)
        let jitter = stride(from: 0.0, to: 10.0, by: 0.05).map {
            MouseSample(t: $0, x: 0.5 + 0.05 * sin($0 * 3), y: 0.5 + 0.05 * cos($0 * 3))
        }
        let plan = plan(zooms: [zoom], moves: jitter)
        let before = plan.camera(at: 4)
        let after = plan.camera(at: 8)
        XCTAssertEqual(before.centerX, after.centerX, accuracy: 0.005)
        XCTAssertEqual(before.centerY, after.centerY, accuracy: 0.005)
    }

    func testCameraFollowsCursorThatLeavesTheVisibleArea() {
        let zoom = ZoomSegment(start: 1, end: 9, focusX: 0.4, focusY: 0.5, focusTime: 2)
        let plan = plan(zooms: [zoom], moves: [MouseSample(t: 0, x: 0.4, y: 0.5), MouseSample(t: 4, x: 0.8, y: 0.5)])
        XCTAssertGreaterThan(plan.camera(at: 8).centerX, 0.59)
    }

    func testTheCameraMovesToEachGroupOfClicksJustBeforeIt() {
        let clicks = [ClickEvent(t: 1, x: 0.2, y: 0.3, down: true), ClickEvent(t: 1.1, x: 0.2, y: 0.3, down: false),
                      ClickEvent(t: 6, x: 0.8, y: 0.7, down: true), ClickEvent(t: 6.1, x: 0.8, y: 0.7, down: false)]
        let zoom = ZoomSegment(start: 0.4, end: 8.6, focusX: 0.2, focusY: 0.3, focusTime: 1)
        let moves = [MouseSample(t: 0, x: 0.2, y: 0.3), MouseSample(t: 5.7, x: 0.8, y: 0.7)]
        let settings = EditSettings()
        let cursor = AutoEditor.cursorTrack(moves: moves, duration: 10, smooth: true)
        let camera = AutoEditor.cameraTrack(zooms: [zoom], clicks: clicks, cursor: cursor, duration: 10, settings: settings)
        let plan = EditPlan(settings: settings, timeMap: .identity(duration: 10), zooms: [zoom], clicks: clicks.filter(\.down),
                            cursorTrack: cursor, cameraTrack: camera)
        // On the first click as it happens, still there a moment before the second, and on the second as it happens
        // (the camera sets off just in time to finish arriving as the click lands).
        XCTAssertEqual(plan.camera(at: 1).centerX, 0.25, accuracy: 0.04)
        XCTAssertEqual(plan.camera(at: 5).centerX, 0.25, accuracy: 0.01)
        XCTAssertEqual(plan.camera(at: 6).centerX, 0.75, accuracy: 0.03)
        XCTAssertEqual(plan.camera(at: 6).centerY, 0.7, accuracy: 0.03)
        XCTAssertEqual(plan.camera(at: 6.5).centerX, 0.75, accuracy: 0.005)
    }

    func testClicksThatFitInViewTogetherDoNotMoveTheCamera() {
        let points: [(Double, Double, Double)] = [(1, 0.40, 0.40), (2.5, 0.48, 0.45), (4, 0.43, 0.52), (5.5, 0.50, 0.42)]
        let clicks = points.flatMap { [ClickEvent(t: $0.0, x: $0.1, y: $0.2, down: true), ClickEvent(t: $0.0 + 0.1, x: $0.1, y: $0.2, down: false)] }
        let moves = points.map { MouseSample(t: $0.0 - 0.3, x: $0.1, y: $0.2) }
        let zooms = AutoEditor.planZooms(clicks: clicks, duration: 10, settings: EditSettings())
        XCTAssertEqual(zooms.count, 1)
        let settings = EditSettings()
        let cursor = AutoEditor.cursorTrack(moves: moves, duration: 10, smooth: true)
        let camera = AutoEditor.cameraTrack(zooms: zooms, clicks: clicks, cursor: cursor, duration: 10, settings: settings)
        let plan = EditPlan(settings: settings, timeMap: .identity(duration: 10), zooms: zooms, clicks: clicks.filter(\.down),
                            cursorTrack: cursor, cameraTrack: camera)
        let first = plan.camera(at: 1.5)
        for t in stride(from: 1.5, through: 6.0, by: 0.25) {
            XCTAssertEqual(plan.camera(at: t).centerX, first.centerX, accuracy: 0.002, "at \(t)")
            XCTAssertEqual(plan.camera(at: t).centerY, first.centerY, accuracy: 0.002, "at \(t)")
        }
    }

    func testTheCameraArrivesWithoutOvershooting() {
        let clicks = [ClickEvent(t: 1, x: 0.7, y: 0.7, down: true), ClickEvent(t: 1.1, x: 0.7, y: 0.7, down: false)]
        let zoom = ZoomSegment(start: 0.4, end: 3.6, focusX: 0.7, focusY: 0.7, focusTime: 1)
        let settings = EditSettings()
        let cursor = AutoEditor.cursorTrack(moves: [MouseSample(t: 0, x: 0.7, y: 0.7)], duration: 6, smooth: true)
        let camera = AutoEditor.cameraTrack(zooms: [zoom], clicks: clicks, cursor: cursor, duration: 6, settings: settings)
        let plan = EditPlan(settings: settings, timeMap: .identity(duration: 6), zooms: [zoom], clicks: clicks.filter(\.down),
                            cursorTrack: cursor, cameraTrack: camera)
        var highest = 0.0
        for step in 0..<600 { highest = max(highest, plan.camera(at: Double(step) / 100).scale) }
        XCTAssertLessThanOrEqual(highest, 2.0 + 1e-6, "no bounce past the zoom level")
        XCTAssertGreaterThan(plan.camera(at: 1.0).scale, 1.9, "zoomed in as the click lands")
        XCTAssertGreaterThan(plan.camera(at: 1.15).scale, 1.999, "and settled a moment later")
    }

    func testTheCursorNeitherRunsAheadOfTheMouseNorTrailsIt() {
        // The mouse flicks across a third of the screen in a tenth of a second, starting at 1 s.
        var moves = [MouseSample(t: 0, x: 0.2, y: 0.5)]
        for step in 1...12 { moves.append(MouseSample(t: 1 + Double(step) / 120, x: 0.2 + 0.33 * Double(step) / 12, y: 0.5)) }
        let track = AutoEditor.cursorTrack(moves: moves, duration: 3, smooth: true)
        let plan = EditPlan(settings: EditSettings(), timeMap: .identity(duration: 3), zooms: [], clicks: [],
                            cursorTrack: track, cameraTrack: SampledTrack(rate: 120, samples: [SIMD3(1, 0.5, 0.5)]))
        XCTAssertEqual(plan.cursor(at: 0.95).x, 0.2, accuracy: 0.003, "still put just before the mouse moves")
        XCTAssertGreaterThan(plan.cursor(at: 1.06).x, 0.32, "keeping up halfway through the flick")
        XCTAssertEqual(plan.cursor(at: 1.16).x, 0.53, accuracy: 0.003, "arrived just after the mouse")
    }

    func testHandTremorIsSmoothedAway() {
        // A still hand wobbling by a couple of points, many times a second.
        let moves = (0..<240).map { MouseSample(t: Double($0) / 120, x: 0.5 + 0.0012 * sin(Double($0) * 2.1), y: 0.5 + 0.0012 * cos(Double($0) * 1.7)) }
        let track = AutoEditor.cursorTrack(moves: moves, duration: 2, smooth: true)
        let plan = EditPlan(settings: EditSettings(), timeMap: .identity(duration: 2), zooms: [], clicks: [],
                            cursorTrack: track, cameraTrack: SampledTrack(rate: 120, samples: [SIMD3(1, 0.5, 0.5)]))
        var worst = 0.0
        for step in 30..<210 { worst = max(worst, abs(plan.cursor(at: Double(step) / 120).x - 0.5)) }
        XCTAssertLessThan(worst, 0.0004, "the wobble is mostly gone")
    }

    func testSmoothedCursorLandsOnTheTargetAndStaysBetweenSamples() {
        let moves = [MouseSample(t: 0, x: 0.1, y: 0.1), MouseSample(t: 1, x: 0.9, y: 0.8)]
        let track = AutoEditor.cursorTrack(moves: moves, duration: 4, smooth: true)
        let plan = EditPlan(settings: EditSettings(), timeMap: .identity(duration: 4), zooms: [], clicks: [],
                            cursorTrack: track, cameraTrack: SampledTrack(rate: 120, samples: [SIMD3(1, 0.5, 0.5)]))
        let end = plan.cursor(at: 3.9)
        XCTAssertEqual(end.x, 0.9, accuracy: 0.01)
        XCTAssertEqual(end.y, 0.8, accuracy: 0.01)
        for step in 0..<400 {
            let point = plan.cursor(at: Double(step) / 100)
            XCTAssertTrue((0.09...0.91).contains(point.x), "x out of range at step \(step): \(point.x)")
        }
    }
}

final class TrimTests: XCTestCase {
    private var input: InputLog {
        InputLog(moves: [MouseSample(t: 5, x: 0.1, y: 0.1), MouseSample(t: 5.5, x: 0.3, y: 0.3)],
                 clicks: [ClickEvent(t: 5, x: 0.1, y: 0.1, down: true), ClickEvent(t: 6, x: 0.3, y: 0.3, down: true)])
    }

    func testTrimsIdleStartAndEndWithMargin() {
        let map = AutoEditor.planTime(input: input, duration: 20, hasAudio: false, settings: EditSettings())
        XCTAssertEqual(map.segments.first?.sourceStart ?? -1, 4, accuracy: 1e-9)
        XCTAssertEqual(map.segments.last?.sourceEnd ?? -1, 7, accuracy: 1e-9)
    }

    func testDoesNotTrimWhenTypingWasNotBeingRecorded() {
        // With no key times, typing is indistinguishable from a quiet mouse, so nothing may be cut.
        let map = AutoEditor.planTime(input: input, duration: 20, hasAudio: false, typingTracked: false, settings: EditSettings())
        XCTAssertEqual(map.outputDuration, 20, accuracy: 1e-9)
        var speedUp = EditSettings()
        speedUp.speedUpIdle = true
        XCTAssertEqual(AutoEditor.planTime(input: input, duration: 20, hasAudio: false, typingTracked: false, settings: speedUp).outputDuration,
                       20, accuracy: 1e-9)
    }

    func testPlanReadsTheManifestToDecideWhetherTrimmingIsSafe() {
        func plan(keysCaptured: Bool?) -> EditPlan {
            let manifest = RecordingManifest(displayID: 0, displayWidth: 100, displayHeight: 100, pixelScale: 1, duration: 20,
                                             hasSystemAudio: false, hasMicrophone: false, keysCaptured: keysCaptured)
            return AutoEditor.makePlan(for: RecordingBundle(folder: URL(fileURLWithPath: "/dev/null"), manifest: manifest,
                                                            input: input, cursors: []))
        }
        XCTAssertEqual(plan(keysCaptured: nil).outputDuration, 20, accuracy: 1e-9)    // older recordings
        XCTAssertEqual(plan(keysCaptured: false).outputDuration, 20, accuracy: 1e-9)
        XCTAssertLessThan(plan(keysCaptured: true).outputDuration, 20)
    }

    func testKeepsEverythingWhenAudioWasRecorded() {
        let map = AutoEditor.planTime(input: input, duration: 20, hasAudio: true, settings: EditSettings())
        XCTAssertEqual(map.outputDuration, 20, accuracy: 1e-9)
    }

    func testTailTrimAppliesEvenWithoutIdleTrimming() {
        var settings = EditSettings()
        settings.trimIdleEnds = false
        settings.trimTail = 5
        let map = AutoEditor.planTime(input: input, duration: 20, hasAudio: false, settings: settings)
        XCTAssertEqual(map.outputDuration, 15, accuracy: 1e-9)
    }

    func testIdleSpeedUpOnlyWhenEnabled() {
        let quiet = InputLog(clicks: [ClickEvent(t: 1, x: 0.5, y: 0.5, down: true), ClickEvent(t: 12, x: 0.5, y: 0.5, down: true)])
        var settings = EditSettings()
        settings.trimIdleEnds = false
        XCTAssertEqual(AutoEditor.planTime(input: quiet, duration: 14, hasAudio: false, settings: settings).segments.count, 1)

        settings.speedUpIdle = true
        let map = AutoEditor.planTime(input: quiet, duration: 14, hasAudio: false, settings: settings)
        XCTAssertTrue(map.segments.contains { $0.speed == settings.idleSpeed })
        XCTAssertLessThan(map.outputDuration, 14)
    }

    func testClicksInTheTrimmedTailDoNotZoom() {
        var settings = EditSettings()
        settings.trimTail = 1
        let log = InputLog(clicks: [ClickEvent(t: 3, x: 0.5, y: 0.5, down: true), ClickEvent(t: 9.5, x: 0.5, y: 0.02, down: true)])
        let bundle = RecordingBundle(folder: URL(fileURLWithPath: "/dev/null"),
                                     manifest: RecordingManifest(displayID: 0, displayWidth: 100, displayHeight: 100,
                                                                 pixelScale: 1, duration: 10, hasSystemAudio: false, hasMicrophone: false),
                                     input: log, cursors: [])
        let plan = AutoEditor.makePlan(for: bundle, settings: settings)
        XCTAssertEqual(plan.zooms.count, 1)
        XCTAssertEqual(plan.zooms[0].focusTime, 3, accuracy: 1e-9)
    }
}

final class RecordingFileTests: XCTestCase {
    func testBundleRoundTrips() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("glide-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }

        let manifest = RecordingManifest(displayID: 7, displayWidth: 1728, displayHeight: 1117, pixelScale: 2,
                                         duration: 12.5, hasSystemAudio: true, hasMicrophone: false)
        let input = InputLog(moves: [MouseSample(t: 0.1, x: 0.2, y: 0.3)],
                             clicks: [ClickEvent(t: 1, x: 0.4, y: 0.5, button: .right, down: true)],
                             scrolls: [ScrollEvent(t: 2, x: 0.5, y: 0.5, dx: 0, dy: -3)],
                             cursors: [CursorChange(t: 0, id: "arrow")])
        let cursors = [CursorImage(id: "arrow", file: "arrow.png", hotspotX: 1, hotspotY: 1, width: 24, height: 24)]
        try RecordingBundle(folder: folder, manifest: manifest, input: input, cursors: cursors).save()

        let loaded = try RecordingBundle.load(from: folder)
        XCTAssertEqual(loaded.input, input)
        XCTAssertEqual(loaded.cursors, cursors)
        XCTAssertEqual(loaded.manifest.displayWidth, 1728)
        XCTAssertEqual(loaded.manifest.duration, 12.5)
        XCTAssertTrue(loaded.manifest.hasSystemAudio)
        XCTAssertEqual(loaded.manifest.formatVersion, 1)
    }
}

/// The whole automatic edit, from a recording to a plan, judged the way a viewer would judge the video.
final class AutomaticEditQualityTests: XCTestCase {
    func testTheDemoRecordingNeedsNoEditing() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("glide-quality-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let bundle = try DemoRecording.make(in: folder)
        let plan = AutoEditor.makePlan(for: bundle, project: EditProject.auto(for: bundle))
        let quality = EditQuality.measure(plan: plan, bundle: bundle)

        XCTAssertGreaterThan(quality.zoomCount, 0, "clicks get zoomed in on")
        XCTAssertEqual(quality.clicksInView, quality.clicks.count, "\(quality)")
        XCTAssertEqual(quality.clicksComfortable, quality.clicks.count, "\(quality)")
        XCTAssertEqual(quality.reversals, 0, "the camera never wobbles\n\(quality)")
        // The zoom eases in over 0.7 s, starting 0.85 s before the click, so it has arrived before the click lands.
        XCTAssertLessThanOrEqual(quality.slowestZoomIn, 0.75, "zoomed in before the click lands")
        XCTAssertLessThan(quality.worstCursorMiss, 5, "the cursor is on the spot it clicks")
    }

    func testARealRecordingIsCalm() {
        // The long Screen Studio recording: about a minute of clicking around one app.
        let recording = ScreenStudioReference.recordings.max { $0.clicks.count < $1.clicks.count }!
        let manifest = RecordingManifest(displayID: 0, displayWidth: 1728, displayHeight: 1117, pixelScale: 1, duration: recording.duration,
                                         hasSystemAudio: false, hasMicrophone: false, keysCaptured: false)
        let moves = recording.clicks.filter(\.down).map { MouseSample(t: $0.t - 0.4, x: $0.x, y: $0.y) }
        let bundle = RecordingBundle(folder: URL(fileURLWithPath: "/dev/null"), manifest: manifest,
                                     input: InputLog(moves: moves, clicks: recording.clicks), cursors: [])
        var settings = EditSettings()
        settings.zoomOnTyping = false
        let plan = AutoEditor.makePlan(for: bundle, project: EditProject.auto(for: bundle, settings: settings))
        let quality = EditQuality.measure(plan: plan, bundle: bundle)
        XCTAssertEqual(quality.zoomCount, 3)
        XCTAssertEqual(quality.clicksComfortable, quality.clicks.count, "\(quality)")
        XCTAssertEqual(quality.reversals, 0, "\(quality)")
        // A minute of clicking moves the camera a handful of times, not at every click.
        XCTAssertLessThanOrEqual(quality.pans, 12, "\(quality)")
    }
}

/// Glide's automatic camera against Screen Studio's, recovered frame by frame from Screen Studio's export of the
/// same recording. This is the check that the automatic edit really behaves like Screen Studio's.
final class ScreenStudioCameraTests: XCTestCase {
    private struct Fixture: Decodable {
        let duration: Double
        let displayWidth: Double
        let displayHeight: Double
        let moves: [[Double]]
        let clicks: [[Value]]
        let camera: [[Double]]

        enum Value: Decodable {
            case number(Double), text(String), flag(Bool)
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let b = try? c.decode(Bool.self) { self = .flag(b) }
                else if let d = try? c.decode(Double.self) { self = .number(d) }
                else { self = .text(try c.decode(String.self)) }
            }
            var number: Double { if case .number(let d) = self { return d }; return 0 }
            var text: String { if case .text(let s) = self { return s }; return "" }
            var flag: Bool { if case .flag(let b) = self { return b }; return false }
        }
    }

    private func load() throws -> (EditPlan, Fixture) {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "screenstudio-camera", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        let clicks = fixture.clicks.map { ClickEvent(t: $0[0].number, x: $0[1].number, y: $0[2].number,
                                                    button: MouseButton(rawValue: $0[3].text) ?? .other, down: $0[4].flag) }
        let input = InputLog(moves: fixture.moves.map { MouseSample(t: $0[0], x: $0[1], y: $0[2]) }, clicks: clicks)
        let manifest = RecordingManifest(displayID: 0, displayWidth: fixture.displayWidth, displayHeight: fixture.displayHeight, pixelScale: 1,
                                         duration: fixture.duration, hasSystemAudio: false, hasMicrophone: false, keysCaptured: true)
        let bundle = RecordingBundle(folder: URL(fileURLWithPath: "/dev/null"), manifest: manifest, input: input, cursors: [])
        var settings = EditSettings()
        settings.zoomOnTyping = false
        return (AutoEditor.makePlan(for: bundle, project: EditProject.auto(for: bundle, settings: settings)), fixture)
    }

    func testEveryZoomEasesInAndOutWithoutBouncing() throws {
        let (plan, fixture) = try load()
        for zoom in plan.zooms {
            // In: the zoom level only ever grows, and the first click's place on screen only ever moves one way.
            let click = AutoEditor.presses(fixture.clicks.map { ClickEvent(t: $0[0].number, x: $0[1].number, y: $0[2].number,
                                                                            button: MouseButton(rawValue: $0[3].text) ?? .other, down: $0[4].flag) })
                .first { $0.down >= zoom.start }!
            var lastScale = 0.0, lastScreenX: Double?, direction = 0.0
            for step in 0...70 {
                let t = zoom.start + Double(step) / 100
                let camera = plan.camera(at: t)
                XCTAssertGreaterThanOrEqual(camera.scale, lastScale - 1e-9, "zoom at \(t) shrank while zooming in")
                XCTAssertLessThanOrEqual(camera.scale, zoom.scale + 1e-9, "zoom at \(t) went past its level")
                lastScale = camera.scale
                let screenX = (click.x - camera.centerX) * camera.scale
                if let last = lastScreenX, abs(screenX - last) > 1e-6 {
                    let now = screenX > last ? 1.0 : -1.0
                    if direction != 0 { XCTAssertEqual(now, direction, "the clicked spot turned back on screen at \(t)") }
                    direction = now
                }
                lastScreenX = screenX
            }
            // Out: the zoom level only ever shrinks, back to the whole screen.
            lastScale = .infinity
            for step in 0...80 {
                let t = zoom.end + Double(step) / 100
                let scale = plan.camera(at: t).scale
                XCTAssertLessThanOrEqual(scale, lastScale + 1e-9, "zoom at \(t) grew while zooming out")
                lastScale = scale
            }
            XCTAssertEqual(lastScale, 1, accuracy: 1e-6)
        }
    }

    func testTheCameraPointsWhereScreenStudioPoints() throws {
        let (plan, fixture) = try load()
        // Screen Studio lets a strip of background show when it zooms near the screen's edge; Glide keeps the zoomed
        // screen filling the video. So Screen Studio's aim is compared after keeping it as far from the edges as Glide's.
        let layout = FrameRenderer.fullLayout(displayWidth: fixture.displayWidth, displayHeight: fixture.displayHeight, style: plan.settings.style)
        let coverage = SIMD2(layout.canvas.width / layout.content.width, layout.canvas.height / layout.content.height)
        var error = 0.0, count = 0
        for sample in fixture.camera where sample[1] > 1.9 {
            let ours = plan.camera(at: sample[0])
            guard ours.scale > 1.9 else { continue }
            let half = SIMD2(0.5 / ours.scale, 0.5 / ours.scale) * coverage
            let theirs = SIMD2(min(max(sample[2], half.x), 1 - half.x), min(max(sample[3], half.y), 1 - half.y))
            error += max(abs(ours.centerX - theirs.x), abs(ours.centerY - theirs.y)); count += 1
        }
        XCTAssertGreaterThan(count, 300)
        XCTAssertLessThan(error / Double(count), 0.03, "share of the screen between the two cameras, on average")
    }

    func testTheCameraMovesWhenScreenStudiosDoes() throws {
        let (plan, fixture) = try load()
        // Moves are judged over a fifth of a second, so the trace's small frame-to-frame jitter is not mistaken for one,
        // and starts closer together than 0.8 s count once.
        func moveStarts(_ track: [(Double, Double, Double)]) -> [Double] {
            var starts: [Double] = []
            var moving = false
            for (a, b) in zip(track, track.dropFirst(6)) where b.0 - a.0 < 0.35 {
                let speed = hypot(b.1 - a.1, b.2 - a.2) / max(1e-6, b.0 - a.0)
                if speed > 0.08 && !moving, starts.last.map({ a.0 - $0 > 0.8 }) ?? true { starts.append(a.0) }
                moving = speed > 0.08
            }
            return starts
        }
        let zoomed = fixture.camera.filter { $0[1] > 1.9 }
        // Moving in and out of a zoom is not a pan; only moves well inside a zoom count.
        let boundaries = plan.zooms.flatMap { [$0.start, $0.end] }
        func insideZoom(_ t: Double) -> Bool { !boundaries.contains { abs($0 - t) < 0.6 } }
        let theirs = moveStarts(zoomed.map { ($0[0], $0[2], $0[3]) }).filter(insideZoom)
        let ours = moveStarts(zoomed.map { sample in let c = plan.camera(at: sample[0]); return (sample[0], c.centerX, c.centerY) }).filter(insideZoom)
        let matched = theirs.filter { t in ours.contains { abs($0 - t) < 0.7 } }
        XCTAssertGreaterThanOrEqual(Double(matched.count), Double(theirs.count) * 0.75, "theirs \(theirs), ours \(ours)")
        XCTAssertLessThanOrEqual(ours.count, theirs.count + 1, "no more camera moves than Screen Studio makes: theirs \(theirs), ours \(ours)")
    }
}


final class TypingSpeedUpTests: XCTestCase {
    /// Three seconds of steady typing from 2 s, with the mouse still.
    private var typing: InputLog {
        InputLog(moves: [MouseSample(t: 0, x: 0.5, y: 0.5)], keys: stride(from: 2.0, through: 5.0, by: 0.2).map { KeyEvent(t: $0) })
    }

    func testTypingPlaysFasterAndTheRestAtNormalSpeed() {
        let map = AutoEditor.planTime(input: typing, duration: 8, hasAudio: false, settings: EditSettings())
        let fast = map.segments.filter { $0.speed > 1 }
        XCTAssertEqual(fast.count, 1)
        XCTAssertEqual(fast[0].speed, 3, accuracy: 1e-9)
        XCTAssertEqual(fast[0].sourceStart, 2.15, accuracy: 0.01, "the first keys at normal speed")
        XCTAssertEqual(fast[0].sourceEnd, 5.15, accuracy: 0.01)
        XCTAssertTrue(map.segments.contains { $0.speed == 1 && $0.sourceEnd <= 2.16 }, "normal speed before the typing")
        XCTAssertLessThan(map.outputDuration, 8 - 1.9, "the video is two seconds shorter")
    }

    func testNarrationIsNeverSpedUp() {
        let map = AutoEditor.planTime(input: typing, duration: 8, hasAudio: true, hasVoice: true, settings: EditSettings())
        XCTAssertFalse(map.segments.contains { $0.speed > 1 })
    }

    func testWithoutKeyTimesNothingIsSpedUp() {
        let map = AutoEditor.planTime(input: typing, duration: 8, hasAudio: false, typingTracked: false, settings: EditSettings())
        XCTAssertFalse(map.segments.contains { $0.speed > 1 })
    }

    func testAFewKeysAreLeftAlone() {
        let short = InputLog(moves: [MouseSample(t: 0, x: 0.5, y: 0.5)], keys: [2.0, 2.2, 2.4, 2.6].map { KeyEvent(t: $0) })
        let map = AutoEditor.planTime(input: short, duration: 8, hasAudio: false, settings: EditSettings())
        XCTAssertFalse(map.segments.contains { $0.speed > 1 })
    }

    func testTheAutomaticEditOfARecordingSpeedsUpItsTyping() {
        let manifest = RecordingManifest(displayID: 0, displayWidth: 1600, displayHeight: 1000, pixelScale: 2, duration: 8,
                                         hasSystemAudio: false, hasMicrophone: false, keysCaptured: true)
        let bundle = RecordingBundle(folder: URL(fileURLWithPath: "/dev/null"), manifest: manifest, input: typing, cursors: [])
        XCTAssertTrue(EditProject.auto(for: bundle).slices.contains { $0.speed > 1 })
    }
}

final class ClickInteractionTests: XCTestCase {

    func testPictureIsStillBeforeTheClickLands() {
        let clicks = [ClickEvent(t: 5, x: 0.2, y: 0.3, down: true), ClickEvent(t: 5.1, x: 0.2, y: 0.3, down: false)]
        let settings = EditSettings()
        let zooms = AutoEditor.planZooms(clicks: clicks, duration: 12, settings: settings)
        let cursor = AutoEditor.cursorTrack(moves: [MouseSample(t: 0, x: 0.2, y: 0.3)], clicks: clicks, duration: 12, smooth: true)
        let camera = AutoEditor.cameraTrack(zooms: zooms, clicks: clicks, moves: [], cursor: cursor, duration: 12, settings: settings)
        func pose(_ t: Double) -> SIMD3<Double> { camera.samples[Int(t * AutoEditor.trackRate)] }
        XCTAssertEqual(pose(5 - 0.1), pose(5), "the camera has stopped a moment before the click")
        XCTAssertEqual(pose(5).x, settings.zoomScale, accuracy: 1e-6)
    }

    func testCursorIsFullyInAtTheClickAndBackAfterRelease() {
        let press = AutoEditor.Press(x: 0.5, y: 0.5, down: 5, up: 5.1)
        var plan = SourcePlan(zooms: [], clicks: [], masks: [], cursorTrack: SampledTrack(rate: 120, samples: [.zero]),
                              cameraTrack: SampledTrack(rate: 120, samples: [.zero]))
        plan.presses = [press]
        XCTAssertEqual(plan.cursorPress(at: 4.9), 0)
        XCTAssertGreaterThan(plan.cursorPress(at: 4.98), 0)
        XCTAssertLessThan(plan.cursorPress(at: 4.98), 1)
        XCTAssertEqual(plan.cursorPress(at: 5), 1, accuracy: 1e-6)
        XCTAssertEqual(plan.cursorPress(at: 5.1), 1, accuracy: 1e-6)
        XCTAssertLessThan(plan.cursorPress(at: 5.16), 1)
        XCTAssertEqual(plan.cursorPress(at: 5.3), 0)
    }

    func testSavedAutomaticZoomsMoveToTheNewLeadAndHandMovedOnesStay() {
        let clicks = [ClickEvent(t: 5, x: 0.2, y: 0.3, down: true), ClickEvent(t: 5.1, x: 0.2, y: 0.3, down: false),
                      ClickEvent(t: 20, x: 0.2, y: 0.3, down: true), ClickEvent(t: 20.1, x: 0.2, y: 0.3, down: false)]
        let manifest = RecordingManifest(displayID: 0, displayWidth: 1728, displayHeight: 1117, pixelScale: 1, duration: 40,
                                         hasSystemAudio: false, hasMicrophone: false, keysCaptured: false)
        let bundle = RecordingBundle(folder: URL(fileURLWithPath: "/dev/null"), manifest: manifest, input: InputLog(moves: [], clicks: clicks), cursors: [])
        var project = EditProject.auto(for: bundle)
        project.formatVersion = 1
        project.settings.clickZoomLead = 0.6
        project.zooms[0].start = 5 - 0.6
        project.zooms[1].start = 18
        project.upgrade(for: bundle)
        XCTAssertEqual(project.zooms[0].start, 5 - 0.85, accuracy: 1e-9)
        XCTAssertEqual(project.zooms[1].start, 18, "moved by hand")
        XCTAssertEqual(project.settings.clickZoomLead, 0.85)
        XCTAssertEqual(project.formatVersion, 2)
    }
}
