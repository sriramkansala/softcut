import AVFoundation
import CoreGraphics
import XCTest
@testable import GlideCore

final class BuiltInMusicTests: XCTestCase {
    func testEveryTrackIsASoundFileThatPlaysAndLoopsWithoutAJump() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        for track in BuiltInMusic.tracks {
            let url = try BuiltInMusic.url(for: track, in: folder)
            let duration = try await AVURLAsset(url: url).load(.duration).seconds
            XCTAssertGreaterThan(duration, 20, track.name)

            let samples = BuiltInMusic.samples(of: track)
            let loudest = samples.lazy.map(abs).max() ?? 0
            XCTAssertEqual(loudest, 0.8, accuracy: 0.001, track.name)
            let seam = abs(samples[0] - samples[samples.count - 2])
            XCTAssertLessThan(seam, 0.2, "\(track.name) would click where it loops")
        }
    }

    func testAMadeTrackIsNotMadeAgain() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try BuiltInMusic.url(for: BuiltInMusic.tracks[0], in: folder)
        let made = try FileManager.default.attributesOfItem(atPath: first.path)[.modificationDate] as? Date
        let second = try BuiltInMusic.url(for: BuiltInMusic.tracks[0], in: folder)
        XCTAssertEqual(made, try FileManager.default.attributesOfItem(atPath: second.path)[.modificationDate] as? Date)
    }
}

final class MaskPainterTests: XCTestCase {
    private func stripes() -> CGImage {
        let context = CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for x in stride(from: 0, to: 200, by: 8) {
            context.setFillColor(x % 16 == 0 ? CGColor(gray: 1, alpha: 1) : CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: x, y: 0, width: 8, height: 100))
        }
        return context.makeImage()!
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    func testAMaskChangesThePictureOnlyInsideItsRectangleAndOnlyWhileItIsShowing() throws {
        let image = stripes()
        let mask = MaskRegion(start: 1, end: 2, rect: CropRect(x: 0, y: 0, width: 0.5, height: 1), kind: .fill)
        let before = pixels(image)

        let hidden = pixels(try XCTUnwrap(MaskPainter.paint(image, masks: [mask], time: 1.5)))
        let inside = (50 * 200 + 50) * 4, outside = (50 * 200 + 164) * 4
        XCTAssertLessThan(hidden[inside], 40, "covered")
        XCTAssertEqual(Int(hidden[outside]), Int(before[outside]), accuracy: 12, "untouched")

        let later = pixels(try XCTUnwrap(MaskPainter.paint(image, masks: [mask], time: 3)))
        XCTAssertEqual(Int(later[inside]), Int(before[inside]), accuracy: 12, "not showing yet")
    }
}
