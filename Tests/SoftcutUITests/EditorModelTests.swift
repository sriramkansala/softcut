import AppKit
import SoftcutCore
import SwiftUI
import XCTest
@testable import SoftcutUI

/// The editing logic behind the editor window. No video is involved: the model only needs a recording's
/// description, and the preview is built separately.
@MainActor
final class EditorModelTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("softcut-ui-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func makeModel(clicks: [Double] = [3, 9], duration: Double = 20) -> EditorModel {
        let manifest = RecordingManifest(displayID: 0, displayWidth: 1600, displayHeight: 1000, pixelScale: 2, duration: duration,
                                         hasSystemAudio: false, hasMicrophone: false, keysCaptured: false)
        let input = InputLog(moves: [MouseSample(t: 0, x: 0.2, y: 0.3), MouseSample(t: 5, x: 0.7, y: 0.6)],
                             clicks: clicks.map { ClickEvent(t: $0, x: 0.4, y: 0.4, down: true) })
        let bundle = RecordingBundle(folder: folder, manifest: manifest, input: input, cursors: [])
        return EditorModel(bundle: bundle)
    }

    func testStartsFromTheAutomaticEdit() {
        let model = makeModel()
        XCTAssertEqual(model.project.zooms.count, 2)
        XCTAssertEqual(model.project.slices.count, 1)
        XCTAssertFalse(model.canUndo)
        XCTAssertFalse(model.canRedo)
    }

    func testThePlayheadMovingDoesNotRedrawThePanels() {
        let model = makeModel()
        var changes = 0
        let watching = model.objectWillChange.sink { changes += 1 }
        model.seek(toOutput: 3)
        XCTAssertEqual(changes, 0, "every panel observes the model, so the playhead must not be published through it")
        XCTAssertEqual(model.clock.time, 3)
        XCTAssertEqual(model.playhead, 3)
        watching.cancel()
    }

    func testUndoAndRedoWalkThroughEdits() {
        let model = makeModel()
        model.edit { $0.settings.style.padding = 0.2 }
        model.edit { $0.settings.style.cornerRadius = 0.04 }
        XCTAssertEqual(model.project.settings.style.cornerRadius, 0.04)

        model.undo()
        XCTAssertEqual(model.project.settings.style.cornerRadius, RenderStyle().cornerRadius)
        XCTAssertEqual(model.project.settings.style.padding, 0.2)
        XCTAssertTrue(model.canRedo)

        model.undo()
        XCTAssertEqual(model.project.settings.style.padding, RenderStyle().padding)
        XCTAssertFalse(model.canUndo)

        model.redo()
        model.redo()
        XCTAssertEqual(model.project.settings.style.cornerRadius, 0.04)
        XCTAssertFalse(model.canRedo)
    }

    func testANewEditClearsRedo() {
        let model = makeModel()
        model.edit { $0.settings.style.padding = 0.2 }
        model.undo()
        XCTAssertTrue(model.canRedo)
        model.edit { $0.settings.style.padding = 0.15 }
        XCTAssertFalse(model.canRedo)
    }

    func testDraggingASliderIsOneUndoStep() {
        let model = makeModel()
        let padding = model.binding(\.settings.style.padding, "padding")
        for step in 1...20 { padding.wrappedValue = 0.05 + Double(step) * 0.005 }
        XCTAssertEqual(model.undoDepth, 1)
        model.undo()
        XCTAssertEqual(model.project.settings.style.padding, RenderStyle().padding)
    }

    func testDifferentSettingsAreSeparateUndoSteps() {
        let model = makeModel()
        model.binding(\.settings.style.padding, "padding").wrappedValue = 0.1
        model.binding(\.settings.style.cornerRadius, "radius").wrappedValue = 0.03
        XCTAssertEqual(model.undoDepth, 2)
    }

    func testAnEditThatChangesNothingIsNotAStep() {
        let model = makeModel()
        model.edit { $0.settings.style.padding = RenderStyle().padding }
        XCTAssertFalse(model.canUndo)
    }

    func testAddingAZoomSelectsItAndUndoDropsIt() {
        let model = makeModel(clicks: [])
        model.seek(toSource: 6)
        model.addZoomAtPlayhead()
        guard case .zoom(let id) = model.selection else { return XCTFail("the new zoom should be selected") }
        let zoom = model.project.zoom(id)!
        XCTAssertLessThanOrEqual(zoom.start, 6)
        XCTAssertGreaterThan(zoom.end, 6)
        // It aims where the mouse was at that moment.
        XCTAssertEqual(zoom.focusX, 0.7, accuracy: 1e-9)

        model.undo()
        XCTAssertNil(model.project.zoom(id))
        XCTAssertEqual(model.selection, .none, "the selection must not point at a zoom that is gone")
    }

    func testSplitDeleteAndRestore() {
        let model = makeModel()
        model.seek(toSource: 8)
        model.splitAtPlayhead()
        XCTAssertEqual(model.project.slices.count, 2)

        model.selection = .slice(model.project.slices[1].id)
        model.deleteSelection()
        XCTAssertEqual(model.project.slices.count, 1)
        XCTAssertEqual(model.outputDuration, 8, accuracy: 1e-9)
        XCTAssertEqual(model.selection, .none)

        model.restoreCuts()
        XCTAssertEqual(model.outputDuration, 20, accuracy: 1e-9)
    }

    func testTrimmingAndSpeedGoThroughTheModel() {
        let model = makeModel()
        let id = model.project.slices[0].id
        model.trimSlice(id, start: 2)
        model.trimSlice(id, end: 12)
        model.setSpeed(id, 2)
        let slice = model.project.slice(id)!
        XCTAssertEqual(slice.sourceStart, 2, accuracy: 1e-9)
        XCTAssertEqual(slice.sourceEnd, 12, accuracy: 1e-9)
        XCTAssertEqual(model.outputDuration, 5, accuracy: 1e-9)
        // Both ends of the same clip are one trimming gesture, so the two trims undo together; the speed is its own step.
        XCTAssertEqual(model.undoDepth, 2)
    }

    func testMovingAndResizingAZoomThroughTheModel() {
        let model = makeModel(clicks: [])
        model.seek(toSource: 5)
        model.addZoomAtPlayhead()
        guard case .zoom(let id) = model.selection else { return XCTFail("selected") }
        let length = model.project.zoom(id)!.end - model.project.zoom(id)!.start

        model.moveZoom(id, toStart: 10)
        XCTAssertEqual(model.project.zoom(id)!.start, 10, accuracy: 1e-9)
        XCTAssertEqual(model.project.zoom(id)!.end - model.project.zoom(id)!.start, length, accuracy: 1e-9)

        model.resizeZoom(id, end: 15)
        XCTAssertEqual(model.project.zoom(id)!.end, 15, accuracy: 1e-9)
    }

    func testDraggingAZoomFollowsThePointerBothWays() {
        // A drag reports the new start over and over as the pointer moves; each update must put the zoom
        // exactly there, not add the whole drag again to where it already moved.
        let model = makeModel(clicks: [3, 14], duration: 30)
        let zoom = model.project.zooms[0]
        let origin = zoom.start
        for offset in [0.2, 0.5, 1.0, 1.5, 1.0, 0.4, -0.5, -1.2] {
            model.moveZoom(zoom.id, toStart: origin + offset)
            XCTAssertEqual(model.project.zoom(zoom.id)!.start, origin + offset, accuracy: 1e-9, "dragged by \(offset)")
            XCTAssertEqual(model.project.zoom(zoom.id)!.end - model.project.zoom(zoom.id)!.start, zoom.end - zoom.start, accuracy: 1e-9)
        }
        // The whole drag is one step to undo.
        model.undo()
        XCTAssertEqual(model.project.zoom(zoom.id)!.start, origin, accuracy: 1e-9)
    }

    func testSavingAndReopening() throws {
        let model = makeModel()
        model.edit { $0.settings.style.padding = 0.18 }
        model.seek(toSource: 8)
        model.splitAtPlayhead()
        model.saveNow()

        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("edit.json").path))
        let reopened = makeModel()
        XCTAssertEqual(reopened.project.settings.style.padding, 0.18)
        XCTAssertEqual(reopened.project.slices.count, 2)
    }

    func testResetGoesBackToTheAutomaticEditAndCanBeUndone() {
        let model = makeModel()
        model.edit { $0.settings.style.padding = 0.2; $0.zooms.removeAll() }
        model.resetToAutomaticEdit()
        XCTAssertEqual(model.project.zooms.count, 2)
        XCTAssertEqual(model.project.settings.style.padding, RenderStyle().padding)
        model.undo()
        XCTAssertEqual(model.project.settings.style.padding, 0.2)
        XCTAssertTrue(model.project.zooms.isEmpty)
    }

    func testBackgroundImageIsCopiedIntoTheRecording() throws {
        let model = makeModel()
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("picked-\(UUID().uuidString).PNG")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        model.setBackgroundImage(from: source)
        XCTAssertEqual(model.project.settings.style.background.kind, .image)
        XCTAssertEqual(model.project.settings.style.background.imageFile, "background.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("background.png").path))
    }

    func testColorBindingReadsAndWritesRGB() {
        let model = makeModel()
        let color = model.colorBinding(\.settings.style.background.solid, "solid")
        color.wrappedValue = Color(.sRGB, red: 0.2, green: 0.4, blue: 0.6)
        let rgb = model.project.settings.style.background.solid
        XCTAssertEqual(rgb.r, 0.2, accuracy: 0.01)
        XCTAssertEqual(rgb.g, 0.4, accuracy: 0.01)
        XCTAssertEqual(rgb.b, 0.6, accuracy: 0.01)

        let shown = model.colorBinding(\.settings.style.background.solid, "solid").wrappedValue
        let back = NSColor(shown).usingColorSpace(.sRGB)!
        XCTAssertEqual(Double(back.greenComponent), 0.4, accuracy: 0.01)
    }
}
