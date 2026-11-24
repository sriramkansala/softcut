import XCTest
@testable import GlideCore

final class TypingBurstTests: XCTestCase {
    private func keys(_ times: [Double], shortcut: Bool = false) -> [KeyEvent] {
        times.map { KeyEvent(t: $0, shortcut: shortcut) }
    }

    func testGroupsKeyPressesAndDropsLoneKeysAndShortcuts() {
        let all = keys([1.0, 1.2, 1.4, 5.0, 9.0, 9.3, 9.6, 9.9]) + keys([3.0, 3.1, 3.2], shortcut: true)
        let bursts = AutoEditor.typingBursts(keys: all, settings: EditSettings())
        XCTAssertEqual(bursts.count, 2)
        XCTAssertEqual(bursts[0].start, 1.0, accuracy: 1e-9)
        XCTAssertEqual(bursts[0].end, 1.4, accuracy: 1e-9)
        XCTAssertEqual(bursts[0].count, 3)
        XCTAssertEqual(bursts[1].count, 4)
    }

    func testPauseLongerThanGapStartsNewBurst() {
        let bursts = AutoEditor.typingBursts(keys: keys([1, 1.2, 1.4, 4, 4.2, 4.4]), settings: EditSettings())
        XCTAssertEqual(bursts.count, 2)
    }
}

final class TypingZoomPlanTests: XCTestCase {
    private let burst = (10.0...10.4).striding(by: 0.1).map { KeyEvent(t: $0) }

    func testTypingBurstBecomesAZoomAimedAtTheCaret() {
        let focus = [FocusSample(t: 10.1, x: 0.3, y: 0.6)]
        let zooms = AutoEditor.planZooms(clicks: [], keys: burst, focus: focus, duration: 30, settings: EditSettings())
        XCTAssertEqual(zooms.count, 1)
        XCTAssertEqual(zooms[0].start, 9.5, accuracy: 1e-9)
        XCTAssertEqual(zooms[0].end, 11.6, accuracy: 1e-9)
        XCTAssertEqual(zooms[0].focusX, 0.3, accuracy: 1e-9)
        XCTAssertEqual(zooms[0].focusY, 0.6, accuracy: 1e-9)
        XCTAssertEqual(zooms[0].scale, EditSettings().typingZoomScale, accuracy: 1e-9)
    }

    func testFallsBackToTheMouseWhenNoCaretWasRecorded() {
        let moves = [MouseSample(t: 2, x: 0.9, y: 0.9), MouseSample(t: 9, x: 0.7, y: 0.2)]
        let zooms = AutoEditor.planZooms(clicks: [], keys: burst, focus: [], moves: moves, duration: 30, settings: EditSettings())
        XCTAssertEqual(zooms.count, 1)
        XCTAssertEqual(zooms[0].focusX, 0.7, accuracy: 1e-9)
        XCTAssertEqual(zooms[0].focusY, 0.2, accuracy: 1e-9)
    }

    func testCanBeTurnedOff() {
        var settings = EditSettings()
        settings.zoomOnTyping = false
        XCTAssertTrue(AutoEditor.planZooms(clicks: [], keys: burst, duration: 30, settings: settings).isEmpty)
    }

    func testClickAndTypingThatTouchBecomeOneZoomWithTheLargerScale() {
        let click = ClickEvent(t: 9.2, x: 0.5, y: 0.5, down: true)
        let zooms = AutoEditor.planZooms(clicks: [click], keys: burst, duration: 30, settings: EditSettings())
        XCTAssertEqual(zooms.count, 1)
        XCTAssertEqual(zooms[0].scale, EditSettings().zoomScale, accuracy: 1e-9)
        XCTAssertEqual(zooms[0].focusTime, 9.2, accuracy: 1e-9)
    }

    func testTypingCountsAsActivityForTrimming() {
        let input = InputLog(clicks: [ClickEvent(t: 2, x: 0.5, y: 0.5, down: true)], keys: burst)
        let map = AutoEditor.planTime(input: input, duration: 30, hasAudio: false, settings: EditSettings())
        // Without keys counted, the last activity would be the click at 2s and the video would end at 3s.
        XCTAssertEqual(map.segments.last?.sourceEnd ?? 0, 11.4, accuracy: 1e-9)
    }
}

final class TypingContextTests: XCTestCase {
    func testTypingLingersAndCaretIsOnlyReportedWhileTyping() {
        let context = TypingContext(keys: [KeyEvent(t: 5), KeyEvent(t: 5.2)],
                                    focus: [FocusSample(t: 5.1, x: 0.2, y: 0.4), FocusSample(t: 5.3, x: 0.25, y: 0.4)])
        XCTAssertFalse(context.isTyping(at: 3))
        XCTAssertTrue(context.isTyping(at: 4.9))   // just ahead of the first key
        XCTAssertTrue(context.isTyping(at: 6.5))   // lingering after the last key
        XCTAssertFalse(context.isTyping(at: 8))
        XCTAssertNil(context.caret(at: 3))
        XCTAssertEqual(context.caret(at: 6)?.x ?? 0, 0.25, accuracy: 1e-9)
        XCTAssertNil(context.caret(at: 8))
    }

    func testShortcutsAreNotTyping() {
        let context = TypingContext(keys: [KeyEvent(t: 5, shortcut: true)], focus: [FocusSample(t: 5, x: 0.5, y: 0.5)])
        XCTAssertFalse(context.isTyping(at: 5))
    }
}

final class CaretFollowingTests: XCTestCase {
    private func plan(focus: [FocusSample]) -> EditPlan {
        let settings = EditSettings()
        let keys = stride(from: 2.0, through: 8.0, by: 0.2).map { KeyEvent(t: $0) }
        let zoom = ZoomSegment(start: 1.5, end: 9.2, focusX: 0.3, focusY: 0.5, focusTime: 2, scale: settings.typingZoomScale)
        // The mouse never moves from the left side.
        let cursor = AutoEditor.cursorTrack(moves: [MouseSample(t: 0, x: 0.3, y: 0.5)], duration: 10, smooth: true)
        let camera = AutoEditor.cameraTrack(zooms: [zoom], cursor: cursor, typing: TypingContext(keys: keys, focus: focus),
                                            duration: 10, settings: settings)
        return EditPlan(settings: settings, timeMap: .identity(duration: 10), zooms: [zoom], clicks: [],
                        cursorTrack: cursor, cameraTrack: camera)
    }

    // The camera keeps its target inside a comfort zone rather than centering on it, so these compare
    // the two cases with each other instead of expecting an exact center.

    private var travellingCaret: [FocusSample] {
        // The caret travels from the left to the right while the mouse stays put.
        stride(from: 2.0, through: 8.0, by: 0.1).map { FocusSample(t: $0, x: 0.3 + 0.4 * ($0 - 2) / 6, y: 0.5) }
    }

    func testCameraFollowsTheCaretAwayFromTheMouse() {
        let withCaret = plan(focus: travellingCaret).camera(at: 8)
        let mouseOnly = plan(focus: []).camera(at: 8)
        XCTAssertGreaterThan(withCaret.centerX, 0.5)
        XCTAssertGreaterThan(withCaret.centerX - mouseOnly.centerX, 0.15)
    }

    func testWithoutCaretSamplesTheCameraStaysWithTheMouse() {
        let center = plan(focus: []).camera(at: 8).centerX
        XCTAssertGreaterThan(center, 0.27)
        XCTAssertLessThan(center, 0.4)
    }

    func testCaretStaysInViewWhileTheCameraFollowsIt() {
        let plan = plan(focus: travellingCaret)
        for step in 30...80 {
            let t = Double(step) / 10
            let caretX = 0.3 + 0.4 * (t - 2) / 6
            let camera = plan.camera(at: t)
            let half = 0.5 / camera.scale
            XCTAssertLessThanOrEqual(abs(caretX - camera.centerX), half, "caret left the view at t=\(t)")
        }
    }
}

final class RecordingCompatibilityTests: XCTestCase {
    func testRecordingsMadeBeforeKeysAndFocusExistedStillLoad() throws {
        let old = """
        {"moves":[{"t":0.1,"x":0.2,"y":0.3}],"clicks":[],"scrolls":[],"cursors":[{"t":0,"id":"arrow"}]}
        """
        let log = try JSONDecoder().decode(InputLog.self, from: Data(old.utf8))
        XCTAssertEqual(log.moves.count, 1)
        XCTAssertTrue(log.keys.isEmpty)
        XCTAssertTrue(log.focus.isEmpty)
    }

    /// Privacy: a key event holds the moment and the shortcut flag, never which key was pressed.
    func testKeyEventsHoldOnlyTimeAndShortcutFlag() throws {
        let data = try JSONEncoder().encode(KeyEvent(t: 1.5, shortcut: true))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["t", "shortcut"])
    }

    func testKeysFocusAndWebcamRoundTripThroughDisk() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("glide-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let manifest = RecordingManifest(displayID: 1, displayWidth: 100, displayHeight: 100, pixelScale: 2, duration: 5,
                                         hasSystemAudio: false, hasMicrophone: true,
                                         webcamFile: "webcam.mov", webcamOffset: -0.25)
        let input = InputLog(keys: [KeyEvent(t: 1), KeyEvent(t: 2, shortcut: true)], focus: [FocusSample(t: 1, x: 0.4, y: 0.6)])
        try RecordingBundle(folder: folder, manifest: manifest, input: input, cursors: []).save()

        let loaded = try RecordingBundle.load(from: folder)
        XCTAssertEqual(loaded.input.keys, input.keys)
        XCTAssertEqual(loaded.input.focus, input.focus)
        XCTAssertEqual(loaded.manifest.webcamFile, "webcam.mov")
        XCTAssertEqual(loaded.manifest.webcamOffset, -0.25)
        // The file does not exist, so the bundle must not offer a webcam to the renderer.
        XCTAssertNil(loaded.webcamURL)
    }
}

final class WebcamTimingTests: XCTestCase {
    func testCameraThatStartedEarlySkipsItsHeadStart() {
        let slice = WebcamTiming.slice(screenStart: 0, screenEnd: 10, offset: -0.4, webcamDuration: 11)
        XCTAssertEqual(slice, WebcamTiming.Slice(sourceStart: 0.4, sourceEnd: 10.4, delay: 0))
    }

    func testCameraThatStartedLateAppearsAfterADelay() {
        let slice = WebcamTiming.slice(screenStart: 0, screenEnd: 10, offset: 1, webcamDuration: 20)
        XCTAssertEqual(slice, WebcamTiming.Slice(sourceStart: 0, sourceEnd: 9, delay: 1))
    }

    func testTrimmedSegmentLooksUpTheMatchingWebcamMoment() {
        let slice = WebcamTiming.slice(screenStart: 4, screenEnd: 6, offset: -0.4, webcamDuration: 30)
        XCTAssertEqual(slice, WebcamTiming.Slice(sourceStart: 4.4, sourceEnd: 6.4, delay: 0))
    }

    func testWebcamThatEndsEarlyIsCutShortAndLaterSegmentsHaveNone() {
        XCTAssertEqual(WebcamTiming.slice(screenStart: 4, screenEnd: 10, offset: 0, webcamDuration: 6),
                       WebcamTiming.Slice(sourceStart: 4, sourceEnd: 6, delay: 0))
        XCTAssertNil(WebcamTiming.slice(screenStart: 8, screenEnd: 10, offset: 0, webcamDuration: 6))
    }
}

private extension ClosedRange where Bound == Double {
    func striding(by step: Double) -> [Double] { Array(stride(from: lowerBound, through: upperBound + 1e-9, by: step)) }
}
