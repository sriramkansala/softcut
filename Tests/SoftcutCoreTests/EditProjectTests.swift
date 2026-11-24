import XCTest
@testable import SoftcutCore

private func bundle(duration: Double = 20, input: InputLog = InputLog(), keysCaptured: Bool? = true) -> RecordingBundle {
    let manifest = RecordingManifest(displayID: 0, displayWidth: 1600, displayHeight: 1000, pixelScale: 2, duration: duration,
                                     hasSystemAudio: false, hasMicrophone: false, keysCaptured: keysCaptured)
    return RecordingBundle(folder: URL(fileURLWithPath: "/dev/null"), manifest: manifest, input: input, cursors: [])
}

final class ProjectFileTests: XCTestCase {
    func testRoundTripsThroughDisk() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("softcut-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        var project = EditProject()
        project.settings.style.padding = 0.12
        project.settings.style.background.kind = .solid
        project.settings.style.webcamCorner = .topLeft
        project.zooms = [ZoomSegment(start: 1, end: 3, focusX: 0.2, focusY: 0.7, focusTime: 1.5, scale: 2.5, follow: .fixed)]
        project.slices = [TimeSegment(sourceStart: 0, sourceEnd: 5, speed: 2)]
        project.audio.muteMicrophone = true
        try project.save(to: folder)

        XCTAssertEqual(EditProject.load(from: folder), project)
    }

    func testFileWithMissingAndUnknownKeysStillLoads() throws {
        // As if written by an older or newer version: no webcam settings, plus a key that does not exist yet.
        let json = """
        {"settings":{"style":{"padding":0.2,"somethingNew":true}},"zooms":[],"slices":[{"sourceStart":0,"sourceEnd":4}],"brandNewField":1}
        """
        let project = try JSONDecoder().decode(EditProject.self, from: Data(json.utf8))
        XCTAssertEqual(project.settings.style.padding, 0.2)
        XCTAssertEqual(project.settings.style.webcamSize, RenderStyle().webcamSize)
        XCTAssertEqual(project.slices.first?.speed, 1)
    }

    func testUnreadableFileMeansNoSavedEdit() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("softcut-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("not json".utf8).write(to: folder.appendingPathComponent("edit.json"))
        XCTAssertNil(EditProject.load(from: folder))
    }

    func testAutoProjectHasZoomsAndFullCoverageWhenNothingIsTrimmed() {
        let input = InputLog(clicks: [ClickEvent(t: 5, x: 0.4, y: 0.4, down: true)])
        let project = EditProject.auto(for: bundle(duration: 12, input: input, keysCaptured: false))
        XCTAssertEqual(project.zooms.count, 1)
        XCTAssertEqual(project.slices.count, 1)
        XCTAssertEqual(project.slices[0].sourceStart, 0)
        XCTAssertEqual(project.slices[0].sourceEnd, 12, accuracy: 1e-9)
    }
}

final class ZoomEditingTests: XCTestCase {
    private func project(_ ranges: [(Double, Double)]) -> EditProject {
        var project = EditProject()
        project.zooms = ranges.map { ZoomSegment(start: $0.0, end: $0.1, focusX: 0.5, focusY: 0.5, focusTime: $0.0) }
        return project
    }

    func testAddsAZoomAtTheTimeAndKeepsThemSorted() {
        var p = project([(10, 12)])
        let id = p.addZoom(at: 3, recordingDuration: 20, aim: SIMD2(0.3, 0.6), scale: 2)
        XCTAssertNotNil(id)
        XCTAssertEqual(p.zooms.map(\.start).sorted(), p.zooms.map(\.start))
        let added = p.zoom(id)!
        XCTAssertLessThanOrEqual(added.start, 3)
        XCTAssertGreaterThan(added.end, 3)
        XCTAssertEqual(added.focusX, 0.3, accuracy: 1e-9)
    }

    func testRefusesToAddInsideAnExistingZoom() {
        var p = project([(4, 8)])
        XCTAssertNil(p.addZoom(at: 6, recordingDuration: 20, aim: SIMD2(0.5, 0.5), scale: 2))
        XCTAssertEqual(p.zooms.count, 1)
    }

    func testNewZoomIsSqueezedIntoTheGapAndRefusedWhenTooSmall() {
        var p = project([(2, 6), (7, 12)])
        let id = p.addZoom(at: 6.2, recordingDuration: 20, aim: SIMD2(0.5, 0.5), scale: 2)
        XCTAssertNotNil(id)
        let added = p.zoom(id)!
        XCTAssertGreaterThanOrEqual(added.start, 6)
        XCTAssertLessThanOrEqual(added.end, 7)

        var tight = project([(2, 6), (6.3, 12)])
        XCTAssertNil(tight.addZoom(at: 6.1, recordingDuration: 20, aim: SIMD2(0.5, 0.5), scale: 2))
    }

    func testResizingStaysClearOfNeighboursAndInsideTheRecording() {
        var p = project([(2, 4), (6, 8)])
        let first = p.zooms[0].id
        p.setZoomRange(first, start: -3, end: 7, recordingDuration: 10)
        XCTAssertEqual(p.zooms[0].start, 0, accuracy: 1e-9)
        XCTAssertEqual(p.zooms[0].end, 6, accuracy: 1e-9)

        let last = p.zooms[1].id
        p.setZoomRange(last, start: 5, end: 50, recordingDuration: 10)
        XCTAssertEqual(p.zooms[1].start, 6, accuracy: 1e-9)
        XCTAssertEqual(p.zooms[1].end, 10, accuracy: 1e-9)
    }

    func testCannotBeShrunkBelowTheMinimumLength() {
        var p = project([(2, 4)])
        p.setZoomRange(p.zooms[0].id, start: 3, end: 3.01, recordingDuration: 10)
        XCTAssertGreaterThanOrEqual(p.zooms[0].end - p.zooms[0].start, EditProject.minimumZoomLength - 1e-9)
    }

    func testMovingKeepsLengthAndStopsAtNeighbours() {
        var p = project([(1, 3), (5, 7), (9, 10)])
        let middle = p.zooms[1].id
        p.moveZoom(middle, by: 10, recordingDuration: 12)
        let moved = p.zoom(middle)!
        XCTAssertEqual(moved.end - moved.start, 2, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(moved.end, 9 + 1e-9)
        p.moveZoom(middle, by: -10, recordingDuration: 12)
        XCTAssertGreaterThanOrEqual(p.zoom(middle)!.start, 3 - 1e-9)
    }

    func testDeleteAndUpdate() {
        var p = project([(1, 3), (5, 7)])
        let id = p.zooms[0].id
        p.updateZoom(id) { $0.scale = 3; $0.follow = .fixed }
        XCTAssertEqual(p.zoom(id)?.scale, 3)
        XCTAssertEqual(p.zoom(id)?.follow, .fixed)
        p.deleteZoom(id)
        XCTAssertEqual(p.zooms.count, 1)
    }

    func testFixedZoomStaysOnItsPointWhileTheMouseLeaves() {
        var settings = EditSettings()
        settings.zoomOnTyping = false
        let moves = [MouseSample(t: 0, x: 0.2, y: 0.5), MouseSample(t: 3, x: 0.85, y: 0.5)]
        var p = EditProject()
        p.settings = settings
        p.zooms = [ZoomSegment(start: 1, end: 9, focusX: 0.35, focusY: 0.5, focusTime: 2, scale: 2, follow: .fixed)]
        let plan = AutoEditor.makePlan(for: bundle(duration: 10, input: InputLog(moves: moves)), project: p)
        XCTAssertEqual(plan.camera(at: 8).centerX, 0.35, accuracy: 0.01)

        p.zooms[0].follow = .auto
        let following = AutoEditor.makePlan(for: bundle(duration: 10, input: InputLog(moves: moves)), project: p)
        XCTAssertGreaterThan(following.camera(at: 8).centerX, 0.5)
    }

    func testDisabledZoomsDoNothing() {
        var p = EditProject()
        p.zooms = [ZoomSegment(start: 1, end: 5, focusX: 0.5, focusY: 0.5, focusTime: 1, scale: 2, isDisabled: true)]
        let plan = AutoEditor.makePlan(for: bundle(duration: 8), project: p)
        XCTAssertEqual(plan.camera(at: 3).scale, 1, accuracy: 0.001)
    }
}

final class SliceEditingTests: XCTestCase {
    private func project() -> EditProject {
        var p = EditProject()
        p.slices = [TimeSegment(sourceStart: 0, sourceEnd: 10)]
        return p
    }

    func testSplitMakesTwoSlicesWithTheSameSpeed() {
        var p = project()
        p.setSliceSpeed(p.slices[0].id, 2)
        XCTAssertTrue(p.split(at: 4))
        XCTAssertEqual(p.slices.count, 2)
        XCTAssertEqual(p.slices[0].sourceEnd, 4)
        XCTAssertEqual(p.slices[1].sourceStart, 4)
        XCTAssertEqual(p.slices.map(\.speed), [2, 2])
        XCTAssertNotEqual(p.slices[0].id, p.slices[1].id)
    }

    func testSplitRefusedNearEdgesAndInCuts() {
        var p = project()
        XCTAssertFalse(p.split(at: 0.05))
        XCTAssertFalse(p.split(at: 9.95))
        XCTAssertFalse(p.split(at: 15))
        XCTAssertEqual(p.slices.count, 1)
    }

    func testDeleteCutsOutAStretchButNeverTheLastOne() {
        var p = project()
        p.split(at: 4)
        p.deleteSlice(p.slices[1].id)
        XCTAssertEqual(p.slices.count, 1)
        XCTAssertEqual(p.timeMap.outputDuration, 4, accuracy: 1e-9)
        p.deleteSlice(p.slices[0].id)
        XCTAssertEqual(p.slices.count, 1)
    }

    func testTrimmingStaysClearOfNeighboursAndInsideTheRecording() {
        var p = project()
        p.split(at: 5)
        p.setSliceRange(p.slices[0].id, start: -2, end: 8, recordingDuration: 10)
        XCTAssertEqual(p.slices[0].sourceStart, 0)
        XCTAssertEqual(p.slices[0].sourceEnd, 5)
        p.setSliceRange(p.slices[1].id, start: 6, end: 99, recordingDuration: 10)
        XCTAssertEqual(p.slices[1].sourceStart, 6)
        XCTAssertEqual(p.slices[1].sourceEnd, 10)
    }

    func testSpeedIsLimitedAndRestoreBringsEverythingBack() {
        var p = project()
        p.split(at: 5)
        p.setSliceSpeed(p.slices[0].id, 100)
        XCTAssertEqual(p.slices[0].speed, 16)
        p.deleteSlice(p.slices[1].id)
        p.restoreAllSlices(recordingDuration: 10)
        XCTAssertEqual(p.slices.count, 1)
        XCTAssertEqual(p.slices[0].sourceEnd, 10)
        XCTAssertEqual(p.slices[0].speed, 1)
    }

    func testOutputTimeOfASourceMomentAcrossCutsAndSpeed() {
        let map = TimeMap(segments: [
            TimeSegment(sourceStart: 2, sourceEnd: 4),
            TimeSegment(sourceStart: 6, sourceEnd: 10, speed: 2),
        ])
        XCTAssertEqual(map.outputTime(forSource: 0), 0, accuracy: 1e-9)       // before the first slice
        XCTAssertEqual(map.outputTime(forSource: 3), 1, accuracy: 1e-9)
        XCTAssertEqual(map.outputTime(forSource: 5), 2, accuracy: 1e-9)       // inside the cut: next picture
        XCTAssertEqual(map.outputTime(forSource: 8), 3, accuracy: 1e-9)       // 2s + (8-6)/2
        XCTAssertEqual(map.outputTime(forSource: 99), map.outputDuration, accuracy: 1e-9)
        XCTAssertTrue(map.keeps(3))
        XCTAssertFalse(map.keeps(5))
    }
}

final class LayoutTests: XCTestCase {
    func testEveryAspectGivesAnEvenCanvasWithTheScreenCenteredInsidePadding() {
        for aspect in AspectChoice.allCases {
            var style = RenderStyle()
            style.aspect = aspect
            let (canvas, content) = FrameRenderer.layout(displayWidth: 1728, displayHeight: 1117, style: style)

            XCTAssertEqual(canvas.width.truncatingRemainder(dividingBy: 2), 0, "\(aspect)")
            XCTAssertEqual(canvas.height.truncatingRemainder(dividingBy: 2), 0, "\(aspect)")
            if let ratio = aspect.ratio {
                XCTAssertEqual(canvas.width / canvas.height, ratio, accuracy: 0.01, "\(aspect)")
            }
            // Inside the canvas, centered, and the shape of the screen is kept.
            XCTAssertGreaterThanOrEqual(content.minX, 0, "\(aspect)")
            XCTAssertLessThanOrEqual(content.maxX, canvas.width, "\(aspect)")
            XCTAssertGreaterThanOrEqual(content.minY, 0, "\(aspect)")
            XCTAssertLessThanOrEqual(content.maxY, canvas.height, "\(aspect)")
            XCTAssertEqual(content.midX, canvas.width / 2, accuracy: 1, "\(aspect)")
            XCTAssertEqual(content.midY, canvas.height / 2, accuracy: 1, "\(aspect)")
            XCTAssertEqual(content.width / content.height, 1728.0 / 1117, accuracy: 0.01, "\(aspect)")
        }
    }

    func testPaddingKeepsTheScreenOffTheEdges() {
        var style = RenderStyle()
        style.aspect = .square
        style.padding = 0.1
        let (canvas, content) = FrameRenderer.layout(displayWidth: 1600, displayHeight: 1000, style: style)
        XCTAssertGreaterThanOrEqual(content.minX, canvas.width * 0.1 - 2)
    }

    func testWiderOutputWidthScalesEverythingProportionally() {
        var small = RenderStyle()
        small.maxOutputWidth = 1280
        var large = RenderStyle()
        large.maxOutputWidth = 2560
        let a = FrameRenderer.layout(displayWidth: 1600, displayHeight: 1000, style: small)
        let b = FrameRenderer.layout(displayWidth: 1600, displayHeight: 1000, style: large)
        XCTAssertEqual(b.canvas.width / a.canvas.width, 2, accuracy: 0.01)
        XCTAssertEqual(b.content.width / a.content.width, 2, accuracy: 0.02)
    }
}
