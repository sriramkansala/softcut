import AppKit
import GlideCore
import SwiftUI
import XCTest
@testable import GlideUI

/// What the Chat tab understands, and that it says so when it doesn't.
@MainActor
final class ChatTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("glide-chat-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: root) }

    private func makeChat() throws -> (EditorChat, EditorModel) {
        let folder = root.appendingPathComponent("main")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest = RecordingManifest(displayID: 0, displayWidth: 1600, displayHeight: 1000, pixelScale: 2, duration: 20,
                                         hasSystemAudio: false, hasMicrophone: false, keysCaptured: false)
        let input = InputLog(moves: [MouseSample(t: 0, x: 0.2, y: 0.3)],
                             clicks: [3, 9, 15].map { ClickEvent(t: $0, x: 0.4, y: 0.4, down: true) })
        let bundle = RecordingBundle(folder: folder, manifest: manifest, input: input, cursors: [])
        try bundle.save()
        let model = EditorModel(bundle: bundle)
        return (EditorChat(model: model), model)
    }

    private func style(_ model: EditorModel) -> RenderStyle { model.project.settings.style }

    func testPuttingTheVideoInADeviceAndTakingItOut() throws {
        try XCTSkipIf(MockupLibrary.shared.entries.isEmpty, "The devices have not been built; see the README.")
        let (chat, model) = try makeChat()
        chat.send("Put it in a MacBook Air 15")
        XCTAssertEqual(style(model).mockup?.deviceID, "macbook-air-15")
        XCTAssertEqual(style(model).mockup?.motionID, "open-from-above", "the device's first motion")

        chat.send("iPhone 18 Pro Max")
        XCTAssertEqual(style(model).mockup?.deviceID, "iphone-18-pro-max", "the longest name wins")

        chat.send("take it out of the device")
        XCTAssertNil(style(model).mockup)
    }

    func testLooseDeviceNames() throws {
        try XCTSkipIf(MockupLibrary.shared.entries.isEmpty, "The devices have not been built; see the README.")
        let (chat, model) = try makeChat()
        chat.send("use a laptop")
        XCTAssertEqual(style(model).mockup?.deviceID, "macbook-pro-14")
        chat.send("macbook pro 16")
        XCTAssertEqual(style(model).mockup?.deviceID, "macbook-pro-16")
        chat.send("a phone")
        XCTAssertEqual(style(model).mockup?.deviceID, "iphone-17")
        chat.send("iphone air")
        XCTAssertEqual(style(model).mockup?.deviceID, "iphone-air")
    }

    func testAskingForAMotion() throws {
        try XCTSkipIf(MockupLibrary.shared.entries.isEmpty, "The devices have not been built; see the README.")
        let (chat, model) = try makeChat()
        chat.send("spin it")
        XCTAssertNil(style(model).mockup)
        XCTAssertTrue(chat.messages.last?.text.contains("isn't in a device") == true)

        chat.send("MacBook Pro 14 turn and open")
        XCTAssertEqual(style(model).mockup?.motionID, "whip-turn", "a motion's own “and” doesn't split the sentence")

        chat.send("slide in from the side")
        XCTAssertEqual(style(model).mockup?.motionID, "slide-in-open")

        chat.send("spin it")
        XCTAssertEqual(style(model).mockup?.motionID, "slide-in-open", "a laptop has no spin")
        XCTAssertTrue(chat.messages.last?.text.contains("can't do that") == true)

        chat.send("iphone 17 spinning")
        XCTAssertEqual(style(model).mockup, MockupChoice(deviceID: "iphone-17", motionID: "spin-in"))
    }

    func testSettingsTakeNumbersAndStayInRange() throws {
        let (chat, model) = try makeChat()
        chat.send("padding 10%")
        XCTAssertEqual(style(model).padding, 0.1, accuracy: 1e-9)
        chat.send("more padding")
        XCTAssertEqual(style(model).padding, 0.13, accuracy: 1e-9)
        chat.send("padding 99")
        XCTAssertEqual(style(model).padding, 0.25, accuracy: 1e-9)
        chat.send("no padding")
        XCTAssertEqual(style(model).padding, 0)
        chat.send("square corners")
        XCTAssertEqual(style(model).cornerRadius, 0)
        XCTAssertEqual(style(model).aspect, .auto, "“square corners” isn't a square video")
        chat.send("make it 9:16")
        XCTAssertEqual(style(model).aspect, .vertical)
        chat.send("no shadow")
        XCTAssertEqual(style(model).shadowOpacity, 0)
        chat.send("hide the cursor")
        XCTAssertFalse(style(model).showCursor)
        chat.send("hide captions")
        XCTAssertFalse(style(model).showCaptions)
    }

    func testBackgrounds() throws {
        let (chat, model) = try makeChat()
        chat.send("use the glacier wallpaper")
        XCTAssertEqual(style(model).background.kind, .wallpaper)
        XCTAssertEqual(style(model).background.wallpaperID, "glacier")
        chat.send("black background")
        XCTAssertEqual(style(model).background.kind, .solid)
        XCTAssertEqual(style(model).background.solid, RGB(hex: 0x000000))
        chat.send("gradient")
        XCTAssertEqual(style(model).background.kind, .gradient)
    }

    func testAtATimeMovesThePlayheadFirst() throws {
        let (chat, model) = try makeChat()
        let splitsBefore = model.project.slices.count
        chat.send("split at 0:05")
        XCTAssertEqual(model.playhead, 5, accuracy: 0.01)
        XCTAssertEqual(model.project.slices.count, splitsBefore + 1)
        chat.send("go to 2 seconds")
        XCTAssertEqual(model.playhead, 2, accuracy: 0.01)
        chat.send("go to the start")
        XCTAssertEqual(model.playhead, 0)
    }

    func testTwoThingsInOneSentenceUndoTogether() throws {
        let (chat, model) = try makeChat()
        let original = model.project
        chat.send("padding 12% and use the ember wallpaper")
        XCTAssertEqual(style(model).padding, 0.12, accuracy: 1e-9)
        XCTAssertEqual(style(model).background.wallpaperID, "ember")

        let reply = try XCTUnwrap(chat.messages.last)
        XCTAssertTrue(chat.canUndo(reply))
        chat.undoLastChange()
        XCTAssertEqual(model.project, original)
    }

    func testTheUndoButtonGoesOnceSomethingElseHasChanged() throws {
        let (chat, model) = try makeChat()
        chat.send("padding 12%")
        let reply = try XCTUnwrap(chat.messages.last)
        XCTAssertTrue(chat.canUndo(reply))
        model.edit { $0.settings.style.padding = 0.2 }
        XCTAssertFalse(chat.canUndo(reply))
        chat.undoLastChange()
        XCTAssertEqual(style(model).padding, 0.2, accuracy: 1e-9, "another change isn't undone by mistake")
    }

    func testItSaysSoWhenItDoesNotFollowAndChangesNothing() throws {
        let (chat, model) = try makeChat()
        let original = model.project
        chat.send("why is the sky blue?")
        XCTAssertEqual(model.project, original)
        XCTAssertTrue(chat.messages.last?.text.contains("didn't understand") == true)

        chat.send("padding 8% and make me a sandwich")
        XCTAssertEqual(style(model).padding, 0.08, accuracy: 1e-9)
        XCTAssertTrue(chat.messages.last?.text.contains("make me a sandwich") == true, "says which part it missed")
    }

    func testHelpAndHistory() throws {
        let (chat, model) = try makeChat()
        chat.send("What can you do?")
        XCTAssertTrue(chat.messages.last?.text.contains("MacBook") == true)
        chat.send("undo")
        XCTAssertTrue(chat.messages.last?.text.contains("nothing to undo") == true)
        chat.send("padding 5%")
        chat.send("undo")
        XCTAssertNotEqual(style(model).padding, 0.05)
        chat.send("redo")
        XCTAssertEqual(style(model).padding, 0.05, accuracy: 1e-9)
        XCTAssertEqual(chat.sent.last, "redo")
    }

    func testReadingTimesAndNumbers() {
        XCTAssertEqual(ChatPhrase("at 1:30").time, 90)
        XCTAssertEqual(ChatPhrase("at 90s").time, 90)
        XCTAssertEqual(ChatPhrase("at 12 seconds").time, 12)
        XCTAssertEqual(ChatPhrase("2 minutes in").time, 120)
        XCTAssertNil(ChatPhrase("make it 16:9").time)
        XCTAssertEqual(ChatPhrase("padding 12.5%").number, 12.5)
        XCTAssertNil(ChatPhrase("at 1:30").number)
    }

    func testTheComposerTurnsKeysIntoActions() {
        _ = NSApplication.shared
        var pressed: [FluidComposerKey] = []
        var handled = true
        var draft = "hello"
        var height: CGFloat = 30
        let text = FluidComposerText(text: Binding(get: { draft }, set: { draft = $0 }),
                                     height: Binding(get: { height }, set: { height = $0 }),
                                     placeholder: "", focusRequest: 0, onFocus: { _ in }, onKey: { key in
            pressed.append(key)
            return handled
        })
        let coordinator = text.makeCoordinator()
        let view = NSTextView(frame: CGRect(x: 0, y: 0, width: 200, height: 40))

        XCTAssertTrue(coordinator.textView(view, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertTrue(coordinator.textView(view, doCommandBy: #selector(NSResponder.moveUp(_:))))
        XCTAssertTrue(coordinator.textView(view, doCommandBy: #selector(NSResponder.moveDown(_:))))
        XCTAssertTrue(coordinator.textView(view, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        XCTAssertEqual(pressed, [.submit, .up, .down, .escape])

        // ↑ and ↓ move the caret as usual when the owner has no use for them.
        handled = false
        XCTAssertFalse(coordinator.textView(view, doCommandBy: #selector(NSResponder.moveUp(_:))))
        // Anything else is left to the text view.
        XCTAssertFalse(coordinator.textView(view, doCommandBy: #selector(NSResponder.deleteBackward(_:))))

        // Away from the first line, ↑ belongs to the caret and the owner doesn't hear of it.
        pressed = []
        handled = true
        view.string = "one\ntwo\nthree"
        view.setSelectedRange(NSRange(location: 5, length: 0))
        XCTAssertFalse(coordinator.textView(view, doCommandBy: #selector(NSResponder.moveUp(_:))))
        XCTAssertFalse(coordinator.textView(view, doCommandBy: #selector(NSResponder.moveDown(_:))))
        XCTAssertEqual(pressed, [])
        view.setSelectedRange(NSRange(location: 1, length: 0))
        XCTAssertTrue(coordinator.textView(view, doCommandBy: #selector(NSResponder.moveUp(_:))))
        XCTAssertEqual(pressed, [.up])
    }

    func testSplittingIntoClauses() {
        XCTAssertEqual(ChatPhrase.clauses(of: "padding 10%, use glacier and then add a zoom").map(\.original),
                       ["padding 10%", "use glacier", "add a zoom"])
        XCTAssertEqual(ChatPhrase.clauses(of: "Rise and open").count, 1)
    }
}
