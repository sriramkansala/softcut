import AVFoundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

/// Builds a synthetic recording: a fake app window, a scripted cursor and three groups
/// of clicks. Lets the editing and rendering pipeline be exercised without screen
/// recording permission, and gives tests a deterministic input.
public enum DemoRecording {
    struct Button {
        let label: String
        let x: Double
        let y: Double
        let clickTimes: [Double]
    }

    static let buttons = [
        Button(label: "New project", x: 0.22, y: 0.32, clickTimes: [3.0]),
        Button(label: "Import", x: 0.70, y: 0.36, clickTimes: [6.0, 6.8]),
        Button(label: "Export", x: 0.84, y: 0.78, clickTimes: [10.5]),
    ]

    public static let duration = 17.5
    static let width = 1440
    static let height = 900
    static let fps = 30

    // Typing happens in a text field far from where the mouse is left (on the Export button),
    // so the camera has to follow the caret rather than the cursor.
    static let phrase = Array("Hello from Glide")
    static let typingStart = 13.5
    static let keyInterval = 0.12
    static let fieldCenter = (x: 0.30, y: 0.62)
    static let fieldWidth = 420.0
    static let textInset = 16.0
    static let textSize = 24.0

    /// The webcam file starts this long before the screen recording, like a real camera that is
    /// switched on first. Its picture shows its own clock, so alignment can be checked by eye.
    static let webcamOffset = -0.4
    static let webcamSize = (width: 1280, height: 720)

    static var keyTimes: [Double] { phrase.indices.map { typingStart + Double($0) * keyInterval } }

    static func typedCount(at time: Double) -> Int { keyTimes.filter { $0 <= time }.count }

    /// Normalized position of the caret after `count` characters have been typed.
    static func caret(afterTyping count: Int) -> (x: Double, y: Double) {
        let left = fieldCenter.x * Double(width) - fieldWidth / 2
        let x = left + textInset + measure(String(phrase.prefix(count)), size: textSize) + 2
        return (x / Double(width), fieldCenter.y)
    }

    static func measure(_ string: String, size: CGFloat) -> Double {
        let font = CTFontCreateWithName("Helvetica Neue" as CFString, size, nil)
        let attributed = NSAttributedString(string: string, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        return CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed), nil, nil, nil)
    }

    /// `variant` changes the picture (a different page color and title) so two demo recordings can be told apart.
    public static func make(in folder: URL, variant: Int = 0) throws -> RecordingBundle {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try writeVideo(to: folder.appendingPathComponent("screen.mov"), variant: variant)

        var moves: [MouseSample] = []
        var clicks: [ClickEvent] = []
        var waypoints: [(t: Double, x: Double, y: Double)] = [(0, 0.5, 0.55)]
        for button in buttons {
            let first = button.clickTimes[0]
            waypoints.append((first - 0.9, waypoints.last!.x, waypoints.last!.y))
            waypoints.append((first, button.x, button.y))
            for time in button.clickTimes.dropFirst() {
                waypoints.append((time - 0.4, button.x + 0.02, button.y + 0.01))
                waypoints.append((time, button.x + 0.02, button.y + 0.01))
            }
            for time in button.clickTimes {
                let at = waypoints.last { $0.t <= time }!
                clicks.append(ClickEvent(t: time, x: at.x, y: at.y, down: true))
                clicks.append(ClickEvent(t: time + 0.08, x: at.x, y: at.y, down: false))
            }
        }
        waypoints.append((duration, waypoints.last!.x, waypoints.last!.y))

        var t = 0.0
        while t <= duration {
            let index = waypoints.lastIndex { $0.t <= t } ?? 0
            let a = waypoints[index]
            let b = waypoints[min(index + 1, waypoints.count - 1)]
            let span = b.t - a.t
            let raw = span > 0 ? (t - a.t) / span : 1
            let eased = raw * raw * (3 - 2 * raw)
            moves.append(MouseSample(t: t, x: a.x + (b.x - a.x) * eased, y: a.y + (b.y - a.y) * eased))
            t += 1.0 / 120
        }
        // Only keep samples where the cursor actually moved, like the real recorder.
        var changed: [MouseSample] = []
        for move in moves where changed.last.map({ $0.x != move.x || $0.y != move.y }) ?? true {
            changed.append(move)
        }

        // The caret is sampled every 100 ms while typing, as the real recorder does.
        var focus: [FocusSample] = []
        var sampleTime = typingStart
        while sampleTime <= keyTimes.last! + 1.0 {
            let position = caret(afterTyping: typedCount(at: sampleTime))
            focus.append(FocusSample(t: sampleTime, x: position.x, y: position.y))
            sampleTime += 0.1
        }

        try writeWebcam(to: folder.appendingPathComponent("webcam.mov"))

        let cursor = try writeArrow(into: folder.appendingPathComponent("cursors", isDirectory: true))
        let manifest = RecordingManifest(displayID: 0, displayWidth: Double(width), displayHeight: Double(height),
                                         pixelScale: 1, duration: duration, hasSystemAudio: false,
                                         hasMicrophone: false, source: "demo",
                                         webcamFile: "webcam.mov", webcamOffset: webcamOffset,
                                         keysCaptured: true, caretTracked: true)
        let input = InputLog(moves: changed, clicks: clicks, scrolls: [],
                             cursors: [CursorChange(t: 0, id: cursor.id)],
                             keys: keyTimes.map { KeyEvent(t: $0) }, focus: focus)
        let bundle = RecordingBundle(folder: folder, manifest: manifest, input: input, cursors: [cursor])
        try bundle.save()
        return bundle
    }

    // MARK: Video

    private static func writeVideo(to url: URL, variant: Int) throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000],
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw GlideError.writerFailed(writer.error?.localizedDescription ?? "") }
        writer.startSession(atSourceTime: .zero)

        let frames = Int(duration * Double(fps))
        for frame in 0..<frames {
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            guard let buffer else { throw GlideError.writerFailed("no pixel buffer") }
            draw(frame: buffer, at: Double(frame) / Double(fps), variant: variant)
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw GlideError.writerFailed(writer.error?.localizedDescription ?? "") }
    }

    private static func draw(frame buffer: CVPixelBuffer, at time: Double, variant: Int) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return }
        // Draw with a top-left origin so positions match the normalized input coordinates.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        ctx.setFillColor(variant == 0 ? CGColor(gray: 0.97, alpha: 1) : CGColor(red: 1.0, green: 0.95, blue: 0.78, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(gray: 0.90, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: 56))
        text(variant == 0 ? "Demo Studio" : "Second recording", in: ctx, at: CGPoint(x: 24, y: 36), size: 22, color: CGColor(gray: 0.2, alpha: 1))
        text(String(format: "%05.2f s", time), in: ctx, at: CGPoint(x: Double(width) - 130, y: 36), size: 20,
             color: CGColor(gray: 0.35, alpha: 1))

        // Motion: a progress bar that keeps moving so frames always change.
        let progress = (time / duration)
        ctx.setFillColor(CGColor(gray: 0.85, alpha: 1))
        ctx.fill(CGRect(x: 80, y: 120, width: Double(width) - 160, height: 14))
        ctx.setFillColor(CGColor(red: 0.2, green: 0.55, blue: 0.95, alpha: 1))
        ctx.fill(CGRect(x: 80, y: 120, width: (Double(width) - 160) * progress, height: 14))

        // Text field with the text typed so far and a caret.
        let field = CGRect(x: fieldCenter.x * Double(width) - fieldWidth / 2, y: fieldCenter.y * Double(height) - 30,
                           width: fieldWidth, height: 60)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.setStrokeColor(CGColor(gray: 0.75, alpha: 1))
        ctx.setLineWidth(2)
        ctx.addPath(CGPath(roundedRect: field, cornerWidth: 10, cornerHeight: 10, transform: nil))
        ctx.drawPath(using: .fillStroke)
        let count = typedCount(at: time)
        if count > 0 {
            text(String(phrase.prefix(count)), in: ctx, at: CGPoint(x: field.minX + textInset, y: field.midY + 8),
                 size: textSize, color: CGColor(gray: 0.1, alpha: 1))
        }
        if time >= typingStart - 0.3 {
            let caretX = caret(afterTyping: count).x * Double(width)
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fill(CGRect(x: caretX, y: field.midY - 16, width: 2, height: 32))
        }

        for button in buttons {
            let clicked = (button.clickTimes.first ?? .infinity) <= time
            let rect = CGRect(x: button.x * Double(width) - 110, y: button.y * Double(height) - 32, width: 220, height: 64)
            let path = CGPath(roundedRect: rect, cornerWidth: 12, cornerHeight: 12, transform: nil)
            ctx.setFillColor(clicked ? CGColor(red: 0.18, green: 0.72, blue: 0.45, alpha: 1)
                                     : CGColor(red: 0.2, green: 0.55, blue: 0.95, alpha: 1))
            ctx.addPath(path)
            ctx.fillPath()
            text(button.label, in: ctx, at: CGPoint(x: rect.minX + 28, y: rect.midY + 8), size: 24,
                 color: CGColor(gray: 1, alpha: 1))
        }
    }

    private static func text(_ string: String, in ctx: CGContext, at point: CGPoint, size: CGFloat, color: CGColor) {
        let font = CTFontCreateWithName("Helvetica Neue" as CFString, size, nil)
        let attributed = NSAttributedString(string: string, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        ctx.saveGState()
        // The context is flipped; flip text back so it reads upright.
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = point
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    // MARK: Webcam

    /// A cartoon face on a moving gradient, with the webcam's own clock in the corner.
    private static func writeWebcam(to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let (w, h) = webcamSize
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 4_000_000],
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw GlideError.writerFailed(writer.error?.localizedDescription ?? "") }
        writer.startSession(atSourceTime: .zero)

        // It runs from before the screen recording starts until after it ends.
        let length = duration - webcamOffset + 0.3
        for frame in 0..<Int(length * Double(fps)) {
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            guard let buffer else { throw GlideError.writerFailed("no pixel buffer") }
            drawFace(into: buffer, size: (w, h), at: Double(frame) / Double(fps))
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw GlideError.writerFailed(writer.error?.localizedDescription ?? "") }
    }

    private static func drawFace(into buffer: CVPixelBuffer, size: (Int, Int), at time: Double) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: size.0, height: size.1,
                                  bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return }
        ctx.translateBy(x: 0, y: CGFloat(size.1))
        ctx.scaleBy(x: 1, y: -1)

        let hue = 0.55 + 0.1 * sin(time)
        ctx.setFillColor(CGColor(red: 0.25 + hue * 0.3, green: 0.35, blue: 0.55 + hue * 0.2, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size.0, height: size.1))

        // Head and eyes bob a little so a still frame cannot hide a timing problem.
        let cx = Double(size.0) / 2 + 40 * sin(time * 1.3)
        let cy = Double(size.1) / 2 + 10 * sin(time * 2.1)
        ctx.setFillColor(CGColor(red: 0.96, green: 0.78, blue: 0.62, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: cx - 170, y: cy - 200, width: 340, height: 400))
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: cx - 90, y: cy - 60, width: 36, height: 44))
        ctx.fillEllipse(in: CGRect(x: cx + 54, y: cy - 60, width: 36, height: 44))
        let mouth = 8 + 26 * abs(sin(time * 5))
        ctx.setFillColor(CGColor(red: 0.6, green: 0.15, blue: 0.2, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: cx - 60, y: cy + 70, width: 120, height: mouth))

        // Low and central so the square, circular crop keeps it in view.
        text(String(format: "cam %.2f", time), in: ctx, at: CGPoint(x: 530, y: 640), size: 52, color: CGColor(gray: 1, alpha: 1))
    }

    // MARK: Cursor

    private static func writeArrow(into folder: URL) throws -> CursorImage {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let scale = 4.0
        let size = 24.0
        let pixels = Int(size * scale)
        let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(pixels))
        ctx.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 2, y: 2))
        path.addLine(to: CGPoint(x: 2, y: 19))
        path.addLine(to: CGPoint(x: 6.5, y: 15))
        path.addLine(to: CGPoint(x: 9.8, y: 22))
        path.addLine(to: CGPoint(x: 12.6, y: 20.8))
        path.addLine(to: CGPoint(x: 9.4, y: 14))
        path.addLine(to: CGPoint(x: 15.5, y: 14))
        path.closeSubpath()
        ctx.addPath(path)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))
        ctx.setLineWidth(1.2)
        ctx.setLineJoin(.round)
        ctx.drawPath(using: .fillStroke)

        let id = "demo-arrow"
        let url = folder.appendingPathComponent("\(id).png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw GlideError.writerFailed("could not write the cursor image")
        }
        CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
        guard CGImageDestinationFinalize(destination) else { throw GlideError.writerFailed("could not write the cursor image") }
        return CursorImage(id: id, file: "\(id).png", hotspotX: 2, hotspotY: 2, width: size, height: size)
    }
}
