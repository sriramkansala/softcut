import AppKit
import GlideCore
import SwiftUI
import XCTest
@testable import GlideUI

/// What the settings panes and the tools on the video ask of the model.
@MainActor
final class PanesAndStageTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("glide-panes-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func makeModel() -> EditorModel {
        let manifest = RecordingManifest(displayID: 0, displayWidth: 1600, displayHeight: 1000, pixelScale: 2, duration: 20,
                                         hasSystemAudio: false, hasMicrophone: false, keysCaptured: false)
        let input = InputLog(moves: [MouseSample(t: 0, x: 0.2, y: 0.3), MouseSample(t: 5, x: 0.7, y: 0.6)],
                             clicks: [3, 9].map { ClickEvent(t: $0, x: 0.4, y: 0.4, down: true) })
        return EditorModel(bundle: RecordingBundle(folder: folder, manifest: manifest, input: input, cursors: []))
    }

    func testAnAreaDrawnOnTheVideoIsHiddenFromThePlayheadAndSelected() throws {
        let model = makeModel()
        model.seek(toOutput: 4)
        let drawn = CropRect(x: 0.1, y: 0.2, width: 0.3, height: 0.25)
        model.addMaskAtPlayhead(rect: drawn)
        let mask = try XCTUnwrap(model.project.masks.first)
        XCTAssertEqual(mask.rect, drawn)
        XCTAssertEqual(mask.start, 4, accuracy: 1e-6)
        XCTAssertEqual(model.selection, .mask(mask.id))
    }

    func testTheAmountSetsEveryCameraZoomButNotAMagnifier() throws {
        let model = makeModel()
        let loupe = try XCTUnwrap(model.project.zooms.first?.id)
        model.updateZoom(loupe, key: "style") { $0.presentation = .loupe; $0.scale = 3 }
        model.setZoomAmount(2.5)
        model.setZoomAmount(2.75)
        XCTAssertEqual(model.project.settings.zoomScale, 2.75)
        XCTAssertEqual(model.project.zoom(loupe)?.scale, 3)
        XCTAssertTrue(model.project.zooms.filter { $0.presentation == .camera }.allSatisfy { $0.scale == 2.75 })
    }

    func testACaptionsFileLandsInTheVideosTimeEvenAfterACut() throws {
        let model = makeModel()
        let clip = try XCTUnwrap(model.project.slices.first?.id)
        model.trimSlice(clip, start: 5)
        let file = folder.appendingPathComponent("lines.srt")
        try "1\n00:00:01,000 --> 00:00:02,500\nHello\n\n2\n00:10:00,000 --> 00:10:01,000\nPast the end\n".write(to: file, atomically: true, encoding: .utf8)
        model.edit { $0.settings.style.showCaptions = false }

        model.importCaptions(from: file)

        XCTAssertEqual(model.project.captions.map(\.text), ["Hello"])
        XCTAssertEqual(model.project.captions[0].start, 6, accuracy: 1e-6, "one second into a clip that starts at five")
        XCTAssertEqual(model.project.captions[0].end, 7.5, accuracy: 1e-6)
        XCTAssertTrue(model.project.settings.style.showCaptions)
    }

    func testAFileWithoutCaptionsKeepsTheOnesThereAndSaysSo() {
        let model = makeModel()
        model.addCaptionAtPlayhead()
        let before = model.project.captions
        let file = folder.appendingPathComponent("empty.srt")
        try? "nothing here".write(to: file, atomically: true, encoding: .utf8)
        model.importCaptions(from: file)
        XCTAssertEqual(model.project.captions, before)
        XCTAssertNotNil(model.notice)
    }
}
