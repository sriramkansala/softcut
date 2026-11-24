import XCTest
@testable import GlideCore

final class ClipOrderTests: XCTestCase {
    private let other = UUID()

    private func map(_ clips: [TimeSegment]) -> TimeMap { TimeMap(segments: clips) }

    func testTheVideoFollowsListOrderNotRecordingOrder() {
        // The second clip is from earlier in the recording than the first.
        let timeMap = map([TimeSegment(sourceStart: 5, sourceEnd: 8), TimeSegment(sourceStart: 1, sourceEnd: 3)])
        XCTAssertEqual(timeMap.outputDuration, 5, accuracy: 1e-9)
        XCTAssertEqual(timeMap.sourceTime(forOutput: 1), 6, accuracy: 1e-9)     // inside the first clip
        XCTAssertEqual(timeMap.sourceTime(forOutput: 3.5), 1.5, accuracy: 1e-9) // inside the second
        XCTAssertEqual(timeMap.outputStarts, [0, 3])
    }

    func testLocatingAMomentTellsWhichRecordingItComesFrom() {
        let timeMap = map([TimeSegment(sourceStart: 0, sourceEnd: 4), TimeSegment(sourceID: other, sourceStart: 10, sourceEnd: 14, speed: 2)])
        let first = timeMap.locate(output: 2)!
        XCTAssertNil(first.segment.sourceID)
        XCTAssertEqual(first.sourceTime, 2, accuracy: 1e-9)
        XCTAssertEqual(first.index, 0)

        let second = timeMap.locate(output: 5)!   // one second into a clip that plays at double speed
        XCTAssertEqual(second.segment.sourceID, other)
        XCTAssertEqual(second.sourceTime, 12, accuracy: 1e-9)
        XCTAssertEqual(second.outputStart, 4, accuracy: 1e-9)

        XCTAssertEqual(timeMap.locate(output: 99)?.index, 1, "past the end stays on the last clip")
    }

    func testSourceMomentsAreFoundPerRecording() {
        let timeMap = map([TimeSegment(sourceStart: 0, sourceEnd: 4), TimeSegment(sourceID: other, sourceStart: 0, sourceEnd: 4)])
        XCTAssertEqual(timeMap.outputTime(forSource: 2), 2, accuracy: 1e-9)
        XCTAssertEqual(timeMap.outputTime(forSource: 2, source: other), 6, accuracy: 1e-9)
        XCTAssertTrue(timeMap.keeps(3, source: other))
        XCTAssertFalse(timeMap.keeps(5, source: other))
    }

    func testARangeUsedByTwoClipsAppearsTwice() {
        let timeMap = map([TimeSegment(sourceStart: 2, sourceEnd: 6), TimeSegment(sourceStart: 0, sourceEnd: 1), TimeSegment(sourceStart: 4, sourceEnd: 8, speed: 2)])
        let pieces = timeMap.pieces(source: nil, sourceStart: 4, sourceEnd: 6)
        XCTAssertEqual(pieces.count, 2)
        XCTAssertEqual(pieces[0], TimeMap.Piece(segmentIndex: 0, outputStart: 2, outputEnd: 4, sourceStart: 4, sourceEnd: 6))
        XCTAssertEqual(pieces[1].segmentIndex, 2)
        XCTAssertEqual(pieces[1].outputStart, 5, accuracy: 1e-9)   // clip starts at 5s of video
        XCTAssertEqual(pieces[1].outputEnd, 6, accuracy: 1e-9)     // 2s of recording at double speed
        XCTAssertTrue(timeMap.pieces(source: other, sourceStart: 0, sourceEnd: 9).isEmpty)
    }
}

final class CutAndPasteTests: XCTestCase {
    private func project() -> EditProject {
        var p = EditProject()
        p.slices = [TimeSegment(sourceStart: 0, sourceEnd: 4), TimeSegment(sourceStart: 4, sourceEnd: 8), TimeSegment(sourceStart: 8, sourceEnd: 12)]
        return p
    }

    func testCuttingAClipAndPastingItAtTheEndMovesIt() {
        var p = project()
        let middle = p.slices[1]
        p.deleteSlice(middle.id)
        XCTAssertEqual(p.slices.map(\.sourceStart), [0, 8])
        let pasted = p.insertSlices([middle], at: p.slices.count)
        XCTAssertEqual(p.slices.map(\.sourceStart), [0, 8, 4])
        XCTAssertEqual(pasted.count, 1)
        XCTAssertNotEqual(pasted[0], middle.id, "a pasted clip is a new clip")
        XCTAssertEqual(p.timeMap.outputDuration, 12, accuracy: 1e-9)
        // What is now last in the video is the stretch that was in the middle of the recording.
        XCTAssertEqual(p.timeMap.sourceTime(forOutput: 9), 5, accuracy: 1e-9)
    }

    func testCopyingLeavesTheOriginalAndMakesAnIndependentCopy() {
        var p = project()
        let original = p.slices[0]
        let copy = p.insertSlices([original], at: 1)[0]
        XCTAssertEqual(p.slices.count, 4)
        XCTAssertEqual(p.slices[1].sourceStart, 0)
        p.setSliceSpeed(copy, 2)
        XCTAssertEqual(p.slices[0].speed, 1, "changing the copy must not change the original")
        XCTAssertEqual(p.slices[1].speed, 2)
    }

    func testMovingAClipEarlierAndLater() {
        var p = project()
        let last = p.slices[2].id
        p.moveSlice(last, toIndex: 0)
        XCTAssertEqual(p.slices.map(\.sourceStart), [8, 0, 4])
        p.moveSlice(last, toIndex: 99)
        XCTAssertEqual(p.slices.map(\.sourceStart), [0, 4, 8])
    }

    func testTrimmingStillStopsAtTheNeighbourInTheRecording() {
        var p = project()
        // Reorder so list neighbours are no longer recording neighbours.
        p.moveSlice(p.slices[2].id, toIndex: 0)          // [8–12, 0–4, 4–8]
        let zeroToFour = p.slices[1].id
        p.setSliceRange(zeroToFour, start: 0, end: 7, recordingDuration: 12)
        XCTAssertEqual(p.slice(zeroToFour)?.sourceEnd ?? 0, 4, accuracy: 1e-9, "must not run into the clip that starts at 4")
    }

    func testPastingCopiesOfTheSameStretchDoesNotConstrainTrimming() {
        var p = project()
        let copy = p.insertSlices([p.slices[1]], at: 3)[0]    // the 4–8 stretch appears twice
        p.setSliceRange(copy, start: 5, end: 7, recordingDuration: 12)
        XCTAssertEqual(p.slice(copy)?.sourceStart ?? 0, 5, accuracy: 1e-9)
        XCTAssertEqual(p.slice(copy)?.sourceEnd ?? 0, 7, accuracy: 1e-9)
    }

    func testSplitByClipID() {
        var p = project()
        let id = p.slices[1].id
        XCTAssertTrue(p.split(clipID: id, atSource: 6))
        XCTAssertEqual(p.slices.map(\.sourceStart), [0, 4, 6, 8])
        XCTAssertFalse(p.split(clipID: id, atSource: 4.05), "too close to the edge")
    }
}

final class AttachedRecordingTests: XCTestCase {
    private func bundle(duration: Double, clicks: [Double] = [2]) -> RecordingBundle {
        // Typing is not tracked, so the automatic edit does not trim the idle ends and the whole recording is kept.
        let manifest = RecordingManifest(displayID: 0, displayWidth: 1600, displayHeight: 1000, pixelScale: 2, duration: duration,
                                         hasSystemAudio: false, hasMicrophone: false, keysCaptured: false)
        let input = InputLog(clicks: clicks.map { ClickEvent(t: $0, x: 0.6, y: 0.4, down: true) })
        return RecordingBundle(folder: URL(fileURLWithPath: "/nowhere"), manifest: manifest, input: input, cursors: [])
    }

    private func attachedProject(extraDuration: Double = 8) -> (EditProject, UUID) {
        var project = EditProject.auto(for: bundle(duration: 10))
        let id = UUID()
        project.attach(AttachedSource(id: id, path: "/nowhere/second", name: "second", duration: extraDuration,
                                      zooms: [ZoomSegment(start: 1, end: 4, focusX: 0.3, focusY: 0.3, focusTime: 1)]),
                       clips: [TimeSegment(sourceStart: 0, sourceEnd: extraDuration)])
        return (project, id)
    }

    func testAttachingPutsItsClipsAtTheEnd() {
        let (project, id) = attachedProject()
        XCTAssertEqual(project.slices.last?.sourceID, id)
        XCTAssertEqual(project.attachments.count, 1)
        XCTAssertEqual(project.timeMap.outputDuration, 10 + 8, accuracy: 1e-9)
    }

    func testAnAttachedRecordingKeepsItsOwnZooms() {
        var (project, id) = attachedProject()
        XCTAssertEqual(project.zooms(of: id).count, 1)
        let zoomID = project.zooms(of: id)[0].id
        XCTAssertEqual(project.locateZoom(zoomID)?.source, id)

        project.updateZoom(zoomID) { $0.scale = 3 }
        XCTAssertEqual(project.zoom(zoomID)?.scale, 3)
        XCTAssertEqual(project.zooms.count, 1, "the main recording's own zooms are untouched")

        // Adding a zoom to the attached recording does not touch the main one.
        let added = project.addZoom(source: id, at: 6, recordingDuration: 8, aim: SIMD2(0.5, 0.5), scale: 2)
        XCTAssertNotNil(added)
        XCTAssertEqual(project.zooms(of: id).count, 2)
        XCTAssertEqual(project.zooms.count, 1)

        project.deleteZoom(zoomID)
        XCTAssertEqual(project.zooms(of: id).count, 1)
    }

    func testResizingAnAttachedZoomStaysInsideThatRecording() {
        var (project, id) = attachedProject(extraDuration: 8)
        let zoomID = project.zooms(of: id)[0].id
        project.setZoomRange(zoomID, start: 1, end: 50, recordingDuration: 8)
        XCTAssertEqual(project.zoom(zoomID)?.end ?? 0, 8, accuracy: 1e-9, "limited by the attached recording's length, not the main one's")
    }

    func testARecordingStaysWhileEditingEvenWithoutClipsSoItsClipCanBePastedBack() {
        var (project, id) = attachedProject()
        let clip = project.slices.last!
        project.deleteSlice(clip.id)
        XCTAssertNotNil(project.attachment(id), "kept, so cut and paste can bring the clip back")
        project.insertSlices([clip], at: project.slices.count)
        XCTAssertEqual(project.slices.last?.sourceID, id)
        XCTAssertNotNil(project.attachment(id))
    }

    func testUnusedRecordingsAreLeftOutOfTheSavedFileButNotOutOfTheProject() throws {
        var (project, id) = attachedProject()
        project.deleteSlice(project.slices.last!.id)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("glide-prune-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        try project.save(to: folder)
        XCTAssertTrue(EditProject.load(from: folder)!.attachments.isEmpty, "the saved file does not carry a recording nothing uses")
        XCTAssertNotNil(project.attachment(id), "the project in memory is untouched")
    }

    func testRestoreEverythingKeepsEachRecordingInTheOrderItAppears() {
        var (project, id) = attachedProject()
        project.split(at: 4)
        project.moveSlice(project.slices.last!.id, toIndex: 0)         // the attached clip goes first
        project.restoreAllSlices(recordingDuration: 10)
        XCTAssertEqual(project.slices.count, 2)
        XCTAssertEqual(project.slices[0].sourceID, id)
        XCTAssertEqual(project.slices[0].sourceEnd, 8, accuracy: 1e-9)
        XCTAssertNil(project.slices[1].sourceID)
        XCTAssertEqual(project.slices[1].sourceEnd, 10, accuracy: 1e-9)
    }

    func testThePlanHasTracksForEachRecordingAndSkipsOnesThatAreMissing() throws {
        let (project, id) = attachedProject()
        let primary = bundle(duration: 10)
        let attached = bundle(duration: 8, clicks: [3])

        var sources = SourceSet(primary: primary)
        sources.add(attached, as: id)
        let plan = AutoEditor.makePlan(sources: sources, project: project)
        XCTAssertEqual(plan.outputDuration, 18, accuracy: 1e-9)
        XCTAssertNotNil(plan.sourcePlan(id))
        XCTAssertEqual(plan.sourcePlan(id)?.zooms.count, 1)
        // The camera of the attached recording is zoomed in during its own zoom, which is 1 to 4 seconds into it.
        XCTAssertGreaterThan(plan.camera(source: id, at: 3).scale, 1.5)
        XCTAssertEqual(plan.camera(source: id, at: 7).scale, 1, accuracy: 0.05)

        // With the attached recording missing, its clips are dropped and the rest still plays.
        let without = AutoEditor.makePlan(sources: SourceSet(primary: primary), project: project)
        XCTAssertEqual(without.outputDuration, 10, accuracy: 1e-9)
        XCTAssertEqual(SourceSet(primary: primary).missing(in: project).count, 1)
        XCTAssertFalse(SourceSet(primary: primary).covers(project))
        XCTAssertTrue(sources.covers(project))
    }

    func testAttachmentsSurviveSaving() throws {
        let (project, id) = attachedProject()
        let decoded = try JSONDecoder().decode(EditProject.self, from: JSONEncoder().encode(project))
        XCTAssertEqual(decoded, project)
        XCTAssertEqual(decoded.attachment(id)?.name, "second")
    }
}

/// Real rendering of two recordings in one video (needs the video frameworks, so it runs outside the sandbox).
@MainActor
final class TwoRecordingRenderTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("glide-two-\(UUID().uuidString)")
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: root) }

    private func pixel(_ image: CGImage, x: Double, y: Double) -> (r: Int, g: Int, b: Int) {
        let data = CFDataGetBytePtr(image.dataProvider!.data!)!
        let bytes = image.bitsPerPixel / 8
        let offset = Int(y * Double(image.height)) * image.bytesPerRow + Int(x * Double(image.width)) * bytes
        // Frames from the video come back with the blue byte first; others with red first.
        if image.bitmapInfo.contains(.byteOrder32Little) { return (Int(data[offset + 2]), Int(data[offset + 1]), Int(data[offset])) }
        return (Int(data[offset]), Int(data[offset + 1]), Int(data[offset + 2]))
    }

    func testTheSecondRecordingAppearsAfterTheFirst() async throws {
        let first = try DemoRecording.make(in: root.appendingPathComponent("first"), variant: 0)
        let second = try DemoRecording.make(in: root.appendingPathComponent("second"), variant: 1)

        var project = EditProject.auto(for: first)
        let id = UUID()
        project.attach(AttachedSource(id: id, path: second.folder.path, name: "second", duration: second.manifest.duration),
                       clips: [TimeSegment(sourceStart: 0, sourceEnd: second.manifest.duration)])
        project.settings.style.showWebcam = false

        var sources = SourceSet(primary: first)
        sources.add(second, as: id)
        let session = try await PreviewSession.make(sources: sources, project: project, previewWidth: 640)
        XCTAssertEqual(session.duration, project.timeMap.outputDuration, accuracy: 0.1)

        // A spot on the page, away from the buttons: gray in the first recording, warm yellow in the second.
        let inFirst = try await session.frame(atOutputTime: 1.0)
        let inSecond = try await session.frame(atOutputTime: first.manifest.duration + 1.0)
        let a = pixel(inFirst, x: 0.2, y: 0.8)
        let b = pixel(inSecond, x: 0.2, y: 0.8)
        XCTAssertGreaterThan(a.b - b.b, 25, "the first page is neutral, the second is yellow (less blue): \(a) vs \(b)")
    }

    func testCuttingAClipAndPastingItAtTheEndReordersWhatIsShown() async throws {
        let first = try DemoRecording.make(in: root.appendingPathComponent("first"), variant: 0)
        let second = try DemoRecording.make(in: root.appendingPathComponent("second"), variant: 1)
        var project = EditProject.auto(for: first)
        project.settings.style.showWebcam = false
        let id = UUID()
        project.attach(AttachedSource(id: id, path: second.folder.path, name: "second", duration: second.manifest.duration),
                       clips: [TimeSegment(sourceStart: 0, sourceEnd: second.manifest.duration)])
        var sources = SourceSet(primary: first)
        sources.add(second, as: id)

        // Cut the first recording's clips (its typing plays faster, so it can be more than one) and paste them at the
        // end: the yellow recording now plays first.
        let clips = project.slices.filter { $0.sourceID == nil }
        for clip in clips { project.deleteSlice(clip.id) }
        project.insertSlices(clips, at: project.slices.count)
        XCTAssertEqual(project.slices.first?.sourceID, id)

        let session = try await PreviewSession.make(sources: sources, project: project, previewWidth: 640)
        let early = try await session.frame(atOutputTime: 1.0)
        let late = try await session.frame(atOutputTime: second.manifest.duration + 1.0)
        XCTAssertGreaterThan(pixel(late, x: 0.2, y: 0.8).b - pixel(early, x: 0.2, y: 0.8).b, 25, "now the neutral page comes last")
    }
}
