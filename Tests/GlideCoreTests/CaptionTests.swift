import XCTest
@testable import GlideCore

final class CaptionBuilderTests: XCTestCase {
    private func words(_ text: String, start: Double, step: Double = 0.3) -> [SpokenWord] {
        text.split(separator: " ").enumerated().map { SpokenWord(text: String($0.element), start: start + Double($0.offset) * step, duration: step * 0.8) }
    }

    func testAShortSentenceIsOneLine() {
        let lines = CaptionBuilder.lines(from: words("Hello there everyone", start: 1), source: nil)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].text, "Hello there everyone")
        XCTAssertEqual(lines[0].start, 1, accuracy: 1e-9)
        XCTAssertGreaterThan(lines[0].end, 1.6)
    }

    func testAPauseStartsANewLine() {
        let spoken = words("First part here", start: 0) + words("Second part here", start: 5)
        let lines = CaptionBuilder.lines(from: spoken, source: nil)
        XCTAssertEqual(lines.map(\.text), ["First part here", "Second part here"])
        // A long silence is not filled with the first line.
        XCTAssertLessThan(lines[0].end, 2)
    }

    func testLongSpeechIsBrokenIntoReadableLines() {
        let spoken = words("this is a long stretch of speech that keeps going without any pause at all for a while", start: 0, step: 0.2)
        let lines = CaptionBuilder.lines(from: spoken, source: nil)
        XCTAssertGreaterThan(lines.count, 1)
        for line in lines { XCTAssertLessThanOrEqual(line.text.count, CaptionBuilder.maxCharacters, line.text) }
        XCTAssertEqual(lines.map(\.text).joined(separator: " "), spoken.map(\.text).joined(separator: " "), "no word is lost or reordered")
    }

    func testTheEndOfASentenceEndsALineOnceItIsLongEnough() {
        let spoken = words("That is how it works. Now let us try it", start: 0, step: 0.25)
        let lines = CaptionBuilder.lines(from: spoken, source: nil)
        XCTAssertEqual(lines.first?.text, "That is how it works.")
    }

    func testLinesBelongToTheRecordingTheyCameFrom() {
        let id = UUID()
        XCTAssertEqual(CaptionBuilder.lines(from: words("Hi there", start: 0), source: id).first?.source, id)
    }

    func testNoWordsMakeNoLines() {
        XCTAssertTrue(CaptionBuilder.lines(from: [], source: nil).isEmpty)
        XCTAssertTrue(CaptionBuilder.lines(from: [SpokenWord(text: "  ", start: 0, duration: 1)], source: nil).isEmpty)
    }
}

final class CaptionModelTests: XCTestCase {
    func testOldProjectsWithoutCaptionsStillOpen() throws {
        let project = try JSONDecoder().decode(EditProject.self, from: Data(#"{"formatVersion":1}"#.utf8))
        XCTAssertTrue(project.captions.isEmpty)
        XCTAssertTrue(project.settings.style.showCaptions)
    }

    func testCaptionsSurviveSaving() throws {
        var project = EditProject()
        project.captions = [CaptionLine(source: UUID(), start: 1, end: 3, text: "Hello"), CaptionLine(start: 4, end: 6, text: "World")]
        project.settings.style.captionSize = 0.04
        project.settings.style.captionPosition = .top
        let again = try JSONDecoder().decode(EditProject.self, from: JSONEncoder().encode(project))
        XCTAssertEqual(again, project)
    }

    func testTheCaptionShowingAtAMomentIsTheOneSpokenThen() {
        var plan = SourcePlan(zooms: [], clicks: [], masks: [],
                              cursorTrack: SampledTrack(rate: 120, samples: [SIMD2(0.5, 0.5)]),
                              cameraTrack: SampledTrack(rate: 120, samples: [SIMD3(1, 0.5, 0.5)]))
        plan.captions = [CaptionLine(start: 1, end: 3, text: "one"), CaptionLine(start: 3, end: 5, text: "two"), CaptionLine(start: 6, end: 7, text: "")]
        XCTAssertNil(plan.caption(at: 0.5))
        XCTAssertEqual(plan.caption(at: 2)?.text, "one")
        XCTAssertEqual(plan.caption(at: 3)?.text, "two")
        XCTAssertNil(plan.caption(at: 5.5))
        XCTAssertNil(plan.caption(at: 6.5), "an empty line shows nothing")
    }

    func testCaptionsAreGivenToTheRecordingTheyBelongTo() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("glide-caption-plan-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let bundle = try DemoRecording.make(in: folder)
        var project = EditProject.auto(for: bundle)
        let other = UUID()
        project.captions = [CaptionLine(start: 1, end: 2, text: "mine"), CaptionLine(source: other, start: 1, end: 2, text: "theirs")]
        let plan = AutoEditor.makePlan(for: bundle, project: project)
        XCTAssertEqual(plan.sourcePlans[nil]?.captions.map(\.text), ["mine"])
    }
}

final class SubtitleFileTests: XCTestCase {
    func testTimesFollowTheFinishedVideo() {
        // The first 4 s are cut, so a caption at 5 s in the recording is at 1 s in the video.
        let map = TimeMap(segments: [TimeSegment(sourceStart: 4, sourceEnd: 20)])
        let srt = SubtitleFile.srt(lines: [CaptionLine(start: 5, end: 7.5, text: "Hello")], timeMap: map)
        XCTAssertEqual(srt, "1\n00:00:01,000 --> 00:00:03,500\nHello\n")
    }

    func testSpeedChangesShortenCaptions() {
        let map = TimeMap(segments: [TimeSegment(sourceStart: 0, sourceEnd: 20, speed: 2)])
        let srt = SubtitleFile.srt(lines: [CaptionLine(start: 4, end: 8, text: "Quick")], timeMap: map)
        XCTAssertTrue(srt.contains("00:00:02,000 --> 00:00:04,000"), srt)
    }

    func testACutInsideALineSplitsItAndTextInCutPartsIsLeftOut() {
        let map = TimeMap(segments: [TimeSegment(sourceStart: 0, sourceEnd: 4), TimeSegment(sourceStart: 6, sourceEnd: 10)])
        let srt = SubtitleFile.srt(lines: [
            CaptionLine(start: 3, end: 7, text: "Across"),
            CaptionLine(start: 4.5, end: 5.5, text: "Gone"),
        ], timeMap: map)
        XCTAssertEqual(srt.components(separatedBy: "Across").count - 1, 2, "one entry for each part that remains")
        XCTAssertFalse(srt.contains("Gone"))
        XCTAssertTrue(srt.hasPrefix("1\n"))
    }

    func testEntriesAreNumberedInOrderAcrossClips() {
        let map = TimeMap(segments: [TimeSegment(sourceStart: 0, sourceEnd: 10)])
        let srt = SubtitleFile.srt(lines: [CaptionLine(start: 6, end: 8, text: "Later"), CaptionLine(start: 1, end: 3, text: "Sooner")], timeMap: map)
        XCTAssertLessThan(srt.range(of: "Sooner")!.lowerBound, srt.range(of: "Later")!.lowerBound)
        XCTAssertTrue(srt.contains("\n2\n"))
    }
}

/// Renders real frames, which needs the video frameworks (so these run outside the sandbox).
@MainActor
final class CaptionRenderTests: XCTestCase {
    private var folder: URL!
    private var bundle: RecordingBundle!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("glide-caption-render-\(UUID().uuidString)")
        bundle = try DemoRecording.make(in: folder)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func frame(_ change: (inout EditProject) -> Void, at time: Double = 4) async throws -> CameraLayoutAndMaskRenderTests.Pixels {
        var project = EditProject.auto(for: bundle)
        project.zooms = []
        project.settings.style.motionBlur = 0
        project.settings.style.showWebcam = false
        project.settings.style.cursorScale = 0.01
        project.settings.style.background.kind = .solid
        change(&project)
        let session = try await PreviewSession.make(bundle: bundle, project: project, previewWidth: 800)
        return CameraLayoutAndMaskRenderTests.Pixels(try await session.frame(atOutputTime: time))
    }

    private let line = CaptionLine(start: 0, end: 20, text: "These words are on screen")
    private let lower = CGRect(x: 0.2, y: 0.78, width: 0.6, height: 0.14)
    private let upper = CGRect(x: 0.2, y: 0.12, width: 0.6, height: 0.14)

    func testACaptionAppearsNearTheBottomAndNowhereElse() async throws {
        let plain = try await frame { _ in }
        let captioned = try await frame { $0.captions = [line] }
        XCTAssertGreaterThan(captioned.difference(from: plain, in: lower), 4, "the caption is drawn in the lower part")
        XCTAssertLessThan(captioned.difference(from: plain, in: upper), 0.5, "and not in the upper part")
    }

    func testPlacingItAtTheTopMovesIt() async throws {
        let plain = try await frame { _ in }
        let top = try await frame {
            $0.captions = [line]
            $0.settings.style.captionPosition = .top
        }
        XCTAssertGreaterThan(top.difference(from: plain, in: upper), 4)
        XCTAssertLessThan(top.difference(from: plain, in: lower), 0.5)
    }

    func testOnlyShowsWhileTheLineIsSpokenAndCanBeTurnedOff() async throws {
        let plain = try await frame { _ in }
        let early = try await frame({ $0.captions = [CaptionLine(start: 6, end: 8, text: "Later")] }, at: 4)
        XCTAssertLessThan(early.difference(from: plain, in: lower), 0.5)

        let hidden = try await frame { project in
            project.captions = [line]
            project.settings.style.showCaptions = false
        }
        XCTAssertLessThan(hidden.difference(from: plain, in: lower), 0.5)
    }

    func testCaptionsFollowTheirClipWhenTheStartIsCut() async throws {
        // A line at 3...4 s of the recording. With the first 2.5 s cut, it is on screen at 0.5...1.5 s of the video.
        var project = EditProject.auto(for: bundle)
        project.zooms = []
        project.slices = [TimeSegment(sourceStart: 2.5, sourceEnd: bundle.manifest.duration)]
        project.captions = [CaptionLine(start: 3, end: 4, text: "Follows the clip")]
        let plan = AutoEditor.makePlan(for: bundle, project: project)
        let location = try XCTUnwrap(plan.timeMap.locate(output: 1))
        XCTAssertEqual(plan.sourcePlans[nil]?.caption(at: location.sourceTime)?.text, "Follows the clip")
        let before = try XCTUnwrap(plan.timeMap.locate(output: 0.2))
        XCTAssertNil(plan.sourcePlans[nil]?.caption(at: before.sourceTime))
    }

    func testEditingTheTextOfACaptionAppliesWithoutRebuilding() async throws {
        var project = EditProject.auto(for: bundle)
        project.captions = [line]
        let session = try await PreviewSession.make(bundle: bundle, project: project, previewWidth: 640)
        project.captions[0].text = "Changed words"
        project.settings.style.captionSize = 0.04
        XCTAssertTrue(session.update(project: project))
    }
}

final class SubtitleFileParsingTests: XCTestCase {
    func testAnSRTFileIsRead() {
        let entries = SubtitleFile.parse("1\r\n00:00:01,500 --> 00:00:03,000\r\nHello <i>there</i>\r\nfriend\r\n\r\n2\r\n00:01:00,000 --> 00:01:02,250\r\nBye\r\n")
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].start, 1.5, accuracy: 1e-9)
        XCTAssertEqual(entries[0].end, 3, accuracy: 1e-9)
        XCTAssertEqual(entries[0].text, "Hello there friend")
        XCTAssertEqual(entries[1].start, 60, accuracy: 1e-9)
    }

    func testAWebVTTFileIsReadWithShortStampsAndCueSettings() {
        let entries = SubtitleFile.parse("WEBVTT\n\nNOTE ignored\n\n00:02.000 --> 00:04.500 align:start\nFirst\n")
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].start, 2, accuracy: 1e-9)
        XCTAssertEqual(entries[0].end, 4.5, accuracy: 1e-9)
        XCTAssertEqual(entries[0].text, "First")
    }

    func testAFileWithNoCuesGivesNothing() {
        XCTAssertTrue(SubtitleFile.parse("this is not subtitles").isEmpty)
    }
}
