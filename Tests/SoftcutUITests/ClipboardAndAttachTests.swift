import SoftcutCore
import XCTest
@testable import SoftcutUI

/// Cutting and pasting clips, and adding more recordings. No video is needed: the model only reads a
/// recording's description, and the preview is built separately.
@MainActor
final class ClipboardAndAttachTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("softcut-clips-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: root) }

    /// Writes a recording folder to disk and returns it.
    @discardableResult
    private func makeRecording(_ name: String, duration: Double, width: Double = 1600, height: Double = 1000, clicks: [Double] = [3]) throws -> RecordingBundle {
        let folder = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest = RecordingManifest(displayID: 0, displayWidth: width, displayHeight: height, pixelScale: 2, duration: duration,
                                         hasSystemAudio: false, hasMicrophone: false, keysCaptured: false)
        let input = InputLog(moves: [MouseSample(t: 0, x: 0.2, y: 0.3), MouseSample(t: 5, x: 0.7, y: 0.6)],
                             clicks: clicks.map { ClickEvent(t: $0, x: 0.4, y: 0.4, down: true) })
        let bundle = RecordingBundle(folder: folder, manifest: manifest, input: input, cursors: [])
        try bundle.save()
        return bundle
    }

    private func model(_ name: String = "main", duration: Double = 20) throws -> EditorModel {
        EditorModel(bundle: try makeRecording(name, duration: duration))
    }

    /// Splits the main recording so there are three clips of 0–6, 6–12, 12–20.
    private func threeClips(_ model: EditorModel) {
        model.seek(toOutput: 6); model.splitAtPlayhead()
        model.seek(toOutput: 12); model.splitAtPlayhead()
    }

    // MARK: Cut, copy, paste

    func testCuttingAClipAndPastingItAtTheEnd() throws {
        let model = try model()
        threeClips(model)
        XCTAssertEqual(model.project.slices.map(\.sourceStart), [0, 6, 12])

        model.selection = .slice(model.project.slices[1].id)
        model.cutSelection()
        XCTAssertEqual(model.project.slices.map(\.sourceStart), [0, 12], "the video closes over the gap")
        XCTAssertEqual(model.outputDuration, 14, accuracy: 1e-9)
        XCTAssertTrue(model.canPaste)

        model.pasteAtEnd()
        XCTAssertEqual(model.project.slices.map(\.sourceStart), [0, 12, 6], "the cut clip is now last")
        XCTAssertEqual(model.outputDuration, 20, accuracy: 1e-9)
        // The new last clip is selected and the playhead is on its first frame.
        XCTAssertEqual(model.selection, .slice(model.project.slices[2].id))
        XCTAssertEqual(model.playhead, 14, accuracy: 1e-9)
    }

    func testCuttingTheLastRemainingClipIsRefused() throws {
        let model = try model()
        model.selection = .slice(model.project.slices[0].id)
        model.cutSelection()
        XCTAssertEqual(model.project.slices.count, 1)
        XCTAssertFalse(model.canPaste)
    }

    func testCopyKeepsTheOriginalAndPasteAddsACopyAfterTheSelectedClip() throws {
        let model = try model()
        threeClips(model)
        let first = model.project.slices[0]
        model.selection = .slice(first.id)
        model.copySelection()
        XCTAssertEqual(model.project.slices.count, 3, "copying removes nothing")

        model.paste()
        XCTAssertEqual(model.project.slices.map(\.sourceStart), [0, 0, 6, 12])
        XCTAssertNotEqual(model.project.slices[1].id, first.id)
        XCTAssertEqual(model.outputDuration, 26, accuracy: 1e-9)
    }

    func testPasteGoesAfterTheClipUnderThePlayheadWhenNothingIsSelected() throws {
        let model = try model()
        threeClips(model)
        model.selection = .slice(model.project.slices[2].id)
        model.copySelection()
        model.selection = .none
        model.seek(toOutput: 3)                        // inside the first clip
        model.paste()
        XCTAssertEqual(model.project.slices.map(\.sourceStart), [0, 12, 6, 12])
    }

    func testPastingTheSameClipTwice() throws {
        let model = try model()
        threeClips(model)
        model.selection = .slice(model.project.slices[0].id)
        model.copySelection()
        model.pasteAtEnd()
        model.pasteAtEnd()
        XCTAssertEqual(model.project.slices.map(\.sourceStart), [0, 6, 12, 0, 0])
        XCTAssertEqual(Set(model.project.slices.map(\.id)).count, 5, "every pasted clip is its own clip")
    }

    func testMovingTheSelectedClip() throws {
        let model = try model()
        threeClips(model)
        model.selection = .slice(model.project.slices[2].id)
        XCTAssertTrue(model.canMoveSelectedClipEarlier)
        XCTAssertFalse(model.canMoveSelectedClipLater)
        model.moveSelectedClip(by: -1)
        XCTAssertEqual(model.project.slices.map(\.sourceStart), [0, 12, 6])
        model.moveSelectedClip(by: -1)
        XCTAssertEqual(model.project.slices.map(\.sourceStart), [12, 0, 6])
        XCTAssertFalse(model.canMoveSelectedClipEarlier)
    }

    func testCutAndPasteCanBeUndoneStepByStep() throws {
        let model = try model()
        threeClips(model)
        let before = model.project.slices
        model.selection = .slice(before[1].id)
        model.cutSelection()
        model.pasteAtEnd()
        model.undo()
        XCTAssertEqual(model.project.slices.map(\.sourceStart), [0, 12])
        model.undo()
        XCTAssertEqual(model.project.slices, before)
    }

    // MARK: Adding recordings

    func testAddingARecordingPutsItAtTheEndAndSelectsIt() throws {
        let model = try model("main", duration: 10)
        let other = try makeRecording("other", duration: 8)
        try model.attachRecording(from: other.folder)

        XCTAssertEqual(model.project.attachments.count, 1)
        XCTAssertEqual(model.project.slices.last?.sourceID, model.project.attachments[0].id)
        XCTAssertEqual(model.outputDuration, 18, accuracy: 1e-9)
        XCTAssertEqual(model.sources.attached.count, 1)
        XCTAssertEqual(model.playhead, 10, accuracy: 1e-9, "the playhead lands where the new recording starts")
        guard case .slice = model.selection else { return XCTFail("the new clip should be selected") }
    }

    func testTheAddedRecordingBringsItsOwnZooms() throws {
        let model = try model("main", duration: 10)
        let other = try makeRecording("other", duration: 8, clicks: [4])
        try model.attachRecording(from: other.folder)
        let id = model.project.attachments[0].id
        XCTAssertEqual(model.project.zooms(of: id).count, 1)
        XCTAssertEqual(model.allZooms.count, model.project.zooms.count + 1)
    }

    func testAZoomAddedOverTheSecondRecordingBelongsToIt() throws {
        let model = try model("main", duration: 10)
        let other = try makeRecording("other", duration: 20, clicks: [])
        try model.attachRecording(from: other.folder)
        let id = model.project.attachments[0].id
        model.selection = .none
        let mainZooms = model.project.zooms.count

        model.seek(toOutput: 10 + 12)                   // 12 seconds into the second recording
        model.addZoomAtPlayhead()
        XCTAssertEqual(model.project.zooms.count, mainZooms, "not added to the main recording")
        XCTAssertEqual(model.project.zooms(of: id).count, 1)
        let zoom = model.project.zooms(of: id)[0]
        XCTAssertLessThanOrEqual(zoom.start, 12)
        XCTAssertGreaterThan(zoom.end, 12)
    }

    func testSplittingInTheSecondRecordingSplitsThatClip() throws {
        let model = try model("main", duration: 10)
        let other = try makeRecording("other", duration: 8, clicks: [])
        try model.attachRecording(from: other.folder)
        let id = model.project.attachments[0].id
        let before = model.project.slices.count

        model.seek(toOutput: 10 + 3)
        model.splitAtPlayhead()
        XCTAssertEqual(model.project.slices.count, before + 1)
        let pieces = model.project.slices.filter { $0.sourceID == id }
        XCTAssertEqual(pieces.map(\.sourceEnd).first ?? 0, 3, accuracy: 1e-9)
        XCTAssertEqual(pieces.last?.sourceStart ?? 0, 3, accuracy: 1e-9)
    }

    func testCuttingAnAttachedClipAndPastingItFirst() throws {
        let model = try model("main", duration: 10)
        let other = try makeRecording("other", duration: 8, clicks: [])
        try model.attachRecording(from: other.folder)
        let id = model.project.attachments[0].id

        let clipLength = model.project.slices.last!.outputDuration
        model.cutSelection()                            // the added clip is selected
        XCTAssertEqual(model.outputDuration, 10, accuracy: 1e-9)
        XCTAssertNotNil(model.project.attachment(id), "kept so the clip can be pasted back")

        model.pasteAtEnd()
        XCTAssertEqual(model.project.slices.last?.sourceID, id)
        XCTAssertNotNil(model.project.attachment(id))
        XCTAssertTrue(model.sources.covers(model.project), "the pasted clip can be played")
        XCTAssertEqual(model.outputDuration, 10 + clipLength, accuracy: 1e-9)
    }

    func testRecordingsThatDoNotFitOrAreAlreadyThereAreRefused() throws {
        let model = try model("main", duration: 10)
        XCTAssertThrowsError(try model.attachRecording(from: model.bundle.folder)) { XCTAssertTrue($0 is AttachError) }

        let narrow = try makeRecording("narrow", duration: 5, width: 900, height: 1600)
        XCTAssertThrowsError(try model.attachRecording(from: narrow.folder)) { error in
            XCTAssertTrue(error.localizedDescription.contains("different shape"))
        }
        XCTAssertTrue(model.project.attachments.isEmpty)

        let fine = try makeRecording("fine", duration: 5)
        try model.attachRecording(from: fine.folder)
        XCTAssertThrowsError(try model.attachRecording(from: fine.folder)) { error in
            XCTAssertTrue(error.localizedDescription.contains("already in this project"))
        }
        XCTAssertEqual(model.project.attachments.count, 1)
    }

    func testSameShapeInADifferentResolutionIsAccepted() throws {
        let model = try model("main", duration: 10)
        let other = try makeRecording("hires", duration: 5, width: 3200, height: 2000)
        XCTAssertNoThrow(try model.attachRecording(from: other.folder))
    }

    func testOnlyRecordingsNotYetInTheProjectCanBeAdded() throws {
        let model = try model("main", duration: 10)
        let a = try makeRecording("a", duration: 5)
        _ = try makeRecording("b", duration: 5)
        try model.attachRecording(from: a.folder)

        func item(_ name: String) -> RecordingItem {
            RecordingItem(folder: root.appendingPathComponent(name), name: name, createdAt: Date(), duration: 5, hasWebcam: false, isEdited: false)
        }
        let offered = model.addable([item("main"), item("a"), item("b")]).map(\.name)
        XCTAssertEqual(offered, ["b"])
    }

    func testAProjectWithAMissingRecordingStillOpensAndOffersToCleanUp() throws {
        let model1 = try model("main", duration: 10)
        let other = try makeRecording("other", duration: 8)
        try model1.attachRecording(from: other.folder)
        model1.saveNow()
        try FileManager.default.removeItem(at: other.folder)         // the recording goes missing

        let reopened = EditorModel(bundle: model1.bundle)
        XCTAssertEqual(reopened.missingRecordings.count, 1)
        XCTAssertNotNil(reopened.notice)
        XCTAssertEqual(reopened.project.slices.count, 2, "the clip is kept in the project in case the recording comes back")

        reopened.removeMissingClips()
        XCTAssertTrue(reopened.missingRecordings.isEmpty)
        XCTAssertEqual(reopened.project.slices.count, 1)
        XCTAssertNil(reopened.notice)
    }
}
