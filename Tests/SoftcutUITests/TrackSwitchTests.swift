import CoreGraphics
import SoftcutCore
import XCTest
@testable import SoftcutUI

/// The switches on the timeline's track headers, and the filmstrip lookup the clips draw from.
@MainActor
final class TrackSwitchTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("softcut-tracks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: root) }

    private func model(microphone: Bool = false, systemAudio: Bool = false) throws -> EditorModel {
        let folder = root.appendingPathComponent("main")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest = RecordingManifest(displayID: 0, displayWidth: 1600, displayHeight: 1000, pixelScale: 2, duration: 20,
                                         hasSystemAudio: systemAudio, hasMicrophone: microphone, keysCaptured: false)
        let input = InputLog(moves: [MouseSample(t: 0, x: 0.2, y: 0.3)],
                             clicks: [3, 9, 15].map { ClickEvent(t: $0, x: 0.4, y: 0.4, down: true) })
        let bundle = RecordingBundle(folder: folder, manifest: manifest, input: input, cursors: [])
        try bundle.save()
        return EditorModel(bundle: bundle)
    }

    func testTheZoomTrackSwitchTurnsEveryZoomOffAndBackOn() throws {
        let model = try model()
        if model.allZooms.isEmpty { model.addZoomAtPlayhead() }
        XCTAssertTrue(model.anyZoomEnabled)

        model.setAllZooms(enabled: false)
        XCTAssertFalse(model.anyZoomEnabled)
        XCTAssertTrue(model.allZooms.allSatisfy { $0.zoom.isDisabled })

        model.undo()
        XCTAssertTrue(model.anyZoomEnabled, "switching a whole track is one step to undo")

        model.setAllZooms(enabled: false)
        model.setAllZooms(enabled: true)
        XCTAssertTrue(model.allZooms.allSatisfy { !$0.zoom.isDisabled })
    }

    func testTheBlurTrackSwitchTurnsEveryHiddenAreaOff() throws {
        let model = try model()
        model.seek(toOutput: 4)
        model.addMaskAtPlayhead()
        XCTAssertTrue(model.anyMaskEnabled)
        model.setAllMasks(enabled: false)
        XCTAssertFalse(model.anyMaskEnabled)
    }

    func testTheVideoTrackSoundSwitchMutesBothRecordedSources() throws {
        let model = try model(microphone: true, systemAudio: true)
        XCTAssertFalse(model.recordedSoundMuted)
        model.setRecordedSoundMuted(true)
        XCTAssertTrue(model.recordedSoundMuted)
        XCTAssertTrue(model.project.audio.muteMicrophone && model.project.audio.muteSystemAudio)
        model.setRecordedSoundMuted(false)
        XCTAssertFalse(model.recordedSoundMuted)
    }

    func testARecordingWithoutSoundCountsAsMuted() throws {
        XCTAssertTrue(try model().recordedSoundMuted)
    }

    func testAFilmstripPicksTheStillNearestAMoment() throws {
        let images = (0..<4).map { index -> CGImage? in
            let context = CGContext(data: nil, width: index + 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            return context?.makeImage()
        }
        let strip = Filmstrip(interval: 2, images: images)
        XCTAssertEqual(strip.image(at: 0)?.width, 1)
        XCTAssertEqual(strip.image(at: 4.5)?.width, 3)
        XCTAssertEqual(strip.image(at: 99)?.width, 4, "past the end, the last still")
        XCTAssertEqual(strip.image(at: -3)?.width, 1, "before the start, the first still")
        // A still that failed to load falls back to one that did.
        let gappy = Filmstrip(interval: 2, images: [nil, images[1]])
        XCTAssertEqual(gappy.image(at: 0)?.width, 2)
    }
}
