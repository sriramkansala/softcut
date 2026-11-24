import AppKit
import SoftcutCore
import XCTest
@testable import SoftcutUI

@MainActor
final class RecorderBarTests: XCTestCase {
    private func pixels(_ model: PreviewRecorderBar) async throws -> NSBitmapImageRep {
        let picture = await RecorderBarSnapshot.render(model)
        return try XCTUnwrap(picture)
    }

    private func isSame(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> Bool {
        a.pixelsWide == b.pixelsWide && a.pixelsHigh == b.pixelsHigh && a.representation(using: .png, properties: [:]) == b.representation(using: .png, properties: [:])
    }

    func testEachStateOfTheBarDrawsAndTheStatesLookDifferent() async throws {
        let idle = try await pixels(PreviewRecorderBar())
        let countdown = try await pixels(PreviewRecorderBar(phase: .countdown(3)))
        let recording = try await pixels(PreviewRecorderBar(phase: .recording(seconds: 72)))
        let saving = try await pixels(PreviewRecorderBar(phase: .saving))
        XCTAssertGreaterThan(idle.pixelsWide, 0)
        XCTAssertFalse(isSame(idle, countdown))
        XCTAssertFalse(isSame(idle, recording))
        XCTAssertFalse(isSame(recording, saving))
        XCTAssertFalse(isSame(countdown, recording))
    }

    func testTheChoicesShowInThePicture() async throws {
        let plain = try await pixels(PreviewRecorderBar())
        let variants: [(String, PreviewRecorderBar)] = [
            ("the picked mode is highlighted", PreviewRecorderBar(mode: .window)),
            ("the area mode too", PreviewRecorderBar(mode: .area)),
            ("a camera shows its name", PreviewRecorderBar(camera: true)),
            ("a microphone shows its name", PreviewRecorderBar(microphone: true)),
            ("system audio shows it is on", PreviewRecorderBar(systemAudio: true)),
        ]
        for (reason, model) in variants {
            let other = try await pixels(model)
            XCTAssertFalse(isSame(plain, other), reason)
        }
    }

    func testTheButtonTitleSaysWhatHappensNext() {
        // Record starts straight away; a window or area is chosen first, and the button says so.
        let titles = RecordMode.allCases.map { RecorderBarView<PreviewRecorderBar>.title(for: $0) }
        XCTAssertEqual(titles, ["Display", "Window", "Area"])
        XCTAssertEqual(Set(RecordMode.allCases.map { RecorderBarView<PreviewRecorderBar>.icon(for: $0) }).count, 3)
    }
}
