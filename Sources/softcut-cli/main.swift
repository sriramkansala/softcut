import AppKit
import AVFoundation
import Foundation
import SoftcutCore
import SoftcutUI
import UniformTypeIdentifiers

let usage = """
softcut-cli: record the screen and produce an edited video.

  softcut-cli record [--seconds N] [--mic] [--system-audio] [--webcam] [--typing] [-o FOLDER]   record, then edit
  softcut-cli edit FOLDER [-o FILE.mp4] [options]                         edit an existing recording
  softcut-cli demo FOLDER [-o FILE.mp4]                                   make a synthetic recording and edit it
  softcut-cli export FOLDER OUT.mp4 [--hevc]                              export the recording's saved edit
  softcut-cli wallpapers [FOLDER]                                         write the built-in wallpapers as SVG files
  softcut-cli stills FOLDER OUTDIR [--width N] [--fresh] T1 T2 ...         render single frames of the edit
  softcut-cli check FOLDER [--fresh]                                      measure how watchable the edit is
  softcut-cli click-timing FOLDER [--sync WORKFOLDER | --live SECONDS [--from S]]    when the mouse, cursor and picture act around each click
  softcut-cli import-screenstudio PROJECT.screenstudio FOLDER               turn a Screen Studio project into a Softcut recording
  softcut-cli bar OUT.png [--mode display|window|area] [--phase idle|countdown|recording|saving] [--camera] [--mic] [--system-audio]
                                                                        draw the recording bar to a picture
  softcut-cli snapshot FOLDER OUT.png [--tab look|cursor|camera|zoom|clip|audio|export] [--time S] [--size WxH] [--zoom N]
                                                                        draw the editor to a picture

Edit options:
  --width N        output width in pixels (default 2560)
  --zoom X         zoom level for clicks (default 2.0)
  --no-zoom        turn off automatic zoom
  --no-cursor      hide the cursor
  --no-webcam      leave the webcam out of the video
  --no-typing-zoom do not zoom while typing
  --no-trim        keep idle time at the start and end
  --speed-idle     play stretches without mouse activity 4x faster
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func value(after flag: String, in args: [String]) -> String? {
    guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
    return args[index + 1]
}

func editSettings(from args: [String]) -> EditSettings {
    var settings = EditSettings()
    if let width = value(after: "--width", in: args).flatMap(Int.init) { settings.style.maxOutputWidth = width }
    if let zoom = value(after: "--zoom", in: args).flatMap(Double.init) { settings.zoomScale = zoom }
    if args.contains("--no-zoom") { settings.autoZoom = false }
    if args.contains("--no-cursor") { settings.style.showCursor = false }
    if args.contains("--no-webcam") { settings.style.showWebcam = false }
    if args.contains("--no-typing-zoom") { settings.zoomOnTyping = false }
    if args.contains("--no-trim") { settings.trimIdleEnds = false }
    if args.contains("--speed-idle") { settings.speedUpIdle = true }
    return settings
}

func render(_ bundle: RecordingBundle, to output: URL, settings: EditSettings) async throws {
    let plan = AutoEditor.makePlan(for: bundle, settings: settings)
    print(String(format: "Recording %.1fs, output %.1fs, %d zoom(s)",
                 bundle.manifest.duration, plan.outputDuration, plan.zooms.count))
    try await Exporter.export(bundle: bundle, plan: plan, to: output) { fraction in
        FileHandle.standardError.write(Data(String(format: "\rRendering %3d%%", Int(fraction * 100)).utf8))
    }
    FileHandle.standardError.write(Data("\n".utf8))
    print("Wrote \(output.path)")
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { print(usage); exit(0) }

do {
    switch command {
    case "demo":
        guard args.count >= 2 else { fail(usage) }
        let folder = URL(fileURLWithPath: args[1])
        let output = value(after: "-o", in: args).map { URL(fileURLWithPath: $0) }
            ?? folder.deletingLastPathComponent().appendingPathComponent(folder.lastPathComponent + ".mp4")
        let bundle = try DemoRecording.make(in: folder, variant: value(after: "--variant", in: args).flatMap(Int.init) ?? 0)
        try await render(bundle, to: output, settings: editSettings(from: args))

    case "edit":
        guard args.count >= 2 else { fail(usage) }
        let folder = URL(fileURLWithPath: args[1])
        let output = value(after: "-o", in: args).map { URL(fileURLWithPath: $0) }
            ?? folder.deletingLastPathComponent().appendingPathComponent(folder.lastPathComponent + ".mp4")
        let bundle = try RecordingBundle.load(from: folder)
        try await render(bundle, to: output, settings: editSettings(from: args))

    case "export":
        // softcut-cli export FOLDER OUT.mp4 [--hevc]: export the recording's saved edit, the way the app's Export button does.
        guard args.count >= 3 else { fail(usage) }
        let bundle = try RecordingBundle.load(from: URL(fileURLWithPath: args[1]))
        let project = EditProject.open(bundle)
        let sources = SourceSet.load(primary: bundle, project: project)
        try await Exporter.export(sources: sources, plan: AutoEditor.makePlan(sources: sources, project: project),
                                  to: URL(fileURLWithPath: args[2]), codec: args.contains("--hevc") ? .hevc : .h264)
        print("Wrote \(args[2])")

    case "wallpapers":
        // softcut-cli wallpapers [FOLDER]: write every built-in wallpaper as an SVG file and show how big they are.
        let folder = URL(fileURLWithPath: args.count > 1 ? args[1] : "wallpapers")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var total = 0
        for wallpaper in Wallpapers.all {
            let svg = Wallpapers.svg(wallpaper, size: CGSize(width: 1600, height: 1000))
            try svg.write(to: folder.appendingPathComponent("\(wallpaper.id).svg"), atomically: true, encoding: .utf8)
            print("\(wallpaper.id).svg  \(svg.utf8.count) bytes")
            total += svg.utf8.count
        }
        print("\(Wallpapers.all.count) wallpapers, \(total) bytes in all")

    case "snapshot":
        guard args.count >= 3 else { fail(usage) }
        _ = NSApplication.shared
        let size = (value(after: "--size", in: args) ?? "1360x880").split(separator: "x").compactMap { Double($0) }
        let tabName = value(after: "--tab", in: args) ?? "look"
        let tab = InspectorTab.allCases.first { $0.rawValue == tabName || $0.title.lowercased() == tabName } ?? .background
        let time = value(after: "--time", in: args).flatMap(Double.init) ?? 1
        let rep = try await EditorSnapshot.render(folder: URL(fileURLWithPath: args[1]),
                                                  size: CGSize(width: size.first ?? 1360, height: size.last ?? 880),
                                                  tab: tab, sideTab: value(after: "--side", in: args).flatMap(EditorSideTab.init(rawValue:)) ?? .media,
                                                  outputTime: time, selectZoom: value(after: "--zoom", in: args).flatMap(Int.init),
                                                  selectSlice: value(after: "--slice", in: args).flatMap(Int.init))
        guard let png = rep.representation(using: .png, properties: [:]) else { fail("Could not make a picture") }
        try png.write(to: URL(fileURLWithPath: args[2]))
        print("Wrote \(args[2]) (\(rep.pixelsWide)x\(rep.pixelsHigh))")

    case "bar":
        // softcut-cli bar OUT.png [--mode display|window|area] [--phase idle|countdown|recording|saving] [--camera] [--mic] [--system-audio]
        guard args.count >= 2 else { fail(usage) }
        _ = NSApplication.shared
        let mode = value(after: "--mode", in: args).flatMap(RecordMode.init(rawValue:)) ?? .display
        let phase: RecorderBarPhase
        switch value(after: "--phase", in: args) {
        case "countdown": phase = .countdown(3)
        case "recording": phase = .recording(seconds: 72)
        case "saving": phase = .saving
        default: phase = .idle
        }
        let model = PreviewRecorderBar(mode: mode, phase: phase, camera: args.contains("--camera"), microphone: args.contains("--mic"),
                                       systemAudio: args.contains("--system-audio"))
        guard let rep = await RecorderBarSnapshot.render(model), let png = rep.representation(using: .png, properties: [:]) else { fail("Could not make a picture") }
        try png.write(to: URL(fileURLWithPath: args[1]))
        print("Wrote \(args[1]) (\(rep.pixelsWide)x\(rep.pixelsHigh))")

    case "mockup-thumbnails":
        // softcut-cli mockup-thumbnails: draw the picture of each device that the Mockups tab shows, into its folder.
        for entry in MockupLibrary.shared.entries {
            let square = entry.family == .iphone
            guard let picture = MockupStudio.still(deviceID: entry.id, motionID: "idle", time: 0,
                                                   canvas: square ? CGSize(width: 480, height: 480) : CGSize(width: 640, height: 480), padding: 12),
                  let png = NSBitmapImageRep(cgImage: picture).representation(using: .png, properties: [:]),
                  let url = MockupLibrary.shared.thumbnailURL(id: entry.id) else { fail("Could not draw \(entry.id)") }
            try png.write(to: url)
            print("Wrote \(url.path)")
        }

    case "mockup-still":
        // softcut-cli mockup-still DEVICE MOTION SECONDS OUT.png [--size 1600x1000] [--screen PICTURE]: one frame of a device on its own.
        guard args.count >= 5 else { fail(usage) }
        let stillSize = (value(after: "--size", in: args) ?? "1600x1000").split(separator: "x").compactMap { Double($0) }
        let screenPicture = value(after: "--screen", in: args).flatMap { CGImageSourceCreateWithURL(URL(fileURLWithPath: $0) as CFURL, nil) }
            .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        guard let still = MockupStudio.still(deviceID: args[1], motionID: args[2], time: Double(args[3]) ?? 100,
                                             canvas: CGSize(width: stillSize[0], height: stillSize[1]), screen: screenPicture),
              let stillPNG = NSBitmapImageRep(cgImage: still).representation(using: .png, properties: [:]) else { fail("Could not draw \(args[1])") }
        try stillPNG.write(to: URL(fileURLWithPath: args[4]))
        print("Wrote \(args[4])")

    case "library-snapshot":
        // softcut-cli library-snapshot ROOT OUT.png: draw the recordings window for the recordings in ROOT.
        guard args.count >= 3 else { fail(usage) }
        _ = NSApplication.shared
        guard let rep = await LibrarySnapshot.render(root: URL(fileURLWithPath: args[1]), size: CGSize(width: 1080, height: 680)),
              let png = rep.representation(using: .png, properties: [:]) else { fail("Could not make a picture") }
        try png.write(to: URL(fileURLWithPath: args[2]))
        print("Wrote \(args[2]) (\(rep.pixelsWide)x\(rep.pixelsHigh))")

    case "fluid-gallery":
        // softcut-cli fluid-gallery OUT.png: draw every Fluid Functionalism component on one page.
        guard args.count >= 2 else { fail(usage) }
        _ = NSApplication.shared
        guard let rep = await FluidGallerySnapshot.render(), let png = rep.representation(using: .png, properties: [:]) else { fail("Could not make a picture") }
        try png.write(to: URL(fileURLWithPath: args[1]))
        print("Wrote \(args[1]) (\(rep.pixelsWide)x\(rep.pixelsHigh))")

    case "stills":
        // softcut-cli stills FOLDER OUTDIR [--width N] [--fresh] T1 T2 ...: render single frames of the edit, without exporting.
        guard args.count >= 4 else { fail(usage) }
        let bundle = try RecordingBundle.load(from: URL(fileURLWithPath: args[1]))
        let project = args.contains("--fresh") ? EditProject.auto(for: bundle) : EditProject.open(bundle)
        let width = value(after: "--width", in: args).flatMap(Int.init) ?? 1280
        let session = try await PreviewSession.make(bundle: bundle, project: project, previewWidth: width)
        let out = URL(fileURLWithPath: args[2])
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        // Times are the arguments that are not options or option values.
        let times = args.indices.dropFirst(3).filter { index in
            !args[index].hasPrefix("--") && args[index - 1] != "--width"
        }.compactMap { Double(args[$0]) }
        for seconds in times {
            let image = try await session.frame(atOutputTime: seconds)
            let url = out.appendingPathComponent(String(format: "still-%06.2f.png", seconds))
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }
        print("Wrote \(times.count) still(s) to \(out.path)")

    case "trace-camera":
        // softcut-cli trace-camera FINISHED.mp4 FOLDER [--fps N] [-o OUT.csv]: recover another app's camera from its export
        // of a recording Softcut also has, and put Softcut's automatic camera next to it.
        guard args.count >= 3 else { fail(usage) }
        let bundle = try RecordingBundle.load(from: URL(fileURLWithPath: args[2]))
        let fps = value(after: "--fps", in: args).flatMap(Double.init) ?? 10
        let (_, samples) = try await CameraTrace.run(finishedURL: URL(fileURLWithPath: args[1]), rawURL: bundle.videoURL,
                                                     fps: fps, duration: bundle.manifest.duration)
        let plan = AutoEditor.makePlan(for: bundle, project: EditProject.auto(for: bundle))
        var csv = "t,their_scale,their_x,their_y,error,softcut_scale,softcut_x,softcut_y\n"
        for sample in samples {
            let ours = plan.camera(at: sample.t)
            csv += String(format: "%.3f,%.3f,%.4f,%.4f,%.2f,%.3f,%.4f,%.4f\n", sample.t, sample.scale, sample.centerX, sample.centerY, sample.error,
                          ours.scale, ours.centerX, ours.centerY)
        }
        let output = value(after: "-o", in: args) ?? bundle.folder.appendingPathComponent("camera-trace.csv").path
        try csv.write(toFile: output, atomically: true, encoding: .utf8)
        print("Wrote \(samples.count) samples to \(output)")

    case "trace-test":
        // softcut-cli trace-test FINISHED.mp4 FOLDER T [S CX CY]...: how well given cameras explain one finished frame.
        let bundle = try RecordingBundle.load(from: URL(fileURLWithPath: args[2]))
        let time = Double(args[3])!
        let finished = try await CameraTrace.FrameReader(url: URL(fileURLWithPath: args[1]), shrink: 1)
        let raw = try await CameraTrace.FrameReader(url: bundle.videoURL, shrink: 2)
        guard let f0 = finished.frame(at: 0.3), let r0 = raw.frame(at: 0.3) else { fail("no frames") }
        let (placement, _) = CameraTrace.findPlacement(finished: f0, raw: r0)
        guard let f = finished.frame(at: time), let r = raw.frame(at: time) else { fail("no frames") }
        let values = args[4...].compactMap(Double.init)
        for i in stride(from: 0, to: values.count - 2, by: 3) {
            let e = CameraTrace.error(finished: f, raw: r, placement: placement, scale: values[i], cx: values[i + 1], cy: values[i + 2])
            print(String(format: "scale %.2f center %.3f, %.3f -> error %.2f", values[i], values[i + 1], values[i + 2], e))
        }
        let best = CameraTrace.locate(finished: f, raw: r, placement: placement, near: nil)
        print(String(format: "search finds scale %.3f center %.3f, %.3f error %.2f", best.scale, best.cx, best.cy, best.error))

    case "compare-trace":
        // softcut-cli compare-trace TRACE.csv FOLDER: how closely Softcut's automatic camera follows a traced camera.
        guard args.count >= 3 else { fail(usage) }
        let bundle = try RecordingBundle.load(from: URL(fileURLWithPath: args[2]))
        let plan = AutoEditor.makePlan(for: bundle, project: EditProject.auto(for: bundle))
        let lines = try String(contentsOfFile: args[1], encoding: .utf8).split(separator: "\n").dropFirst()
        var scaleError = 0.0, centerError = 0.0, scaleCount = 0, centerCount = 0
        var transitionError = 0.0, transitionCount = 0
        var worst: [(Double, Double)] = []
        var theirs: [(t: Double, s: Double, x: Double, y: Double)] = []
        for line in lines {
            let v = line.split(separator: ",").compactMap { Double($0) }
            guard v.count >= 5, v[4] < 10 else { continue }   // skip frames the trace could not explain well
            theirs.append((v[0], v[1], v[2], v[3]))
        }
        for sample in theirs {
            let ours = plan.camera(at: sample.t)
            scaleError += abs(ours.scale - sample.s); scaleCount += 1
            if sample.s > 1.05 && sample.s < 1.95 || ours.scale > 1.05 && ours.scale < 1.95 { transitionError += abs(ours.scale - sample.s); transitionCount += 1 }
            if sample.s > 1.9 && ours.scale > 1.9 {
                let d = max(abs(ours.centerX - sample.x), abs(ours.centerY - sample.y))
                centerError += d; centerCount += 1
                worst.append((sample.t, d))
            }
        }
        // Camera moves: stretches where the center travels faster than 5% of the screen per second.
        func moves(_ track: [(t: Double, x: Double, y: Double)]) -> [Double] {
            var starts: [Double] = []
            var moving = false
            for (a, b) in zip(track, track.dropFirst()) {
                let speed = hypot(b.x - a.x, b.y - a.y) / max(1e-6, b.t - a.t)
                if speed > 0.05 && !moving { starts.append(b.t) }
                moving = speed > 0.05
            }
            return starts
        }
        let zoomedTheirs = theirs.filter { $0.s > 1.9 }.map { (t: $0.t, x: $0.x, y: $0.y) }
        let zoomedOurs = theirs.filter { $0.s > 1.9 }.map { sample -> (t: Double, x: Double, y: Double) in
            let c = plan.camera(at: sample.t); return (sample.t, c.centerX, c.centerY)
        }
        print(String(format: "Zoom level: off by %.3f on average (%.3f while zooming in or out)", scaleError / Double(max(1, scaleCount)),
                     transitionError / Double(max(1, transitionCount))))
        print(String(format: "Where the camera points while zoomed: off by %.3f of the screen on average", centerError / Double(max(1, centerCount))))
        print("Camera moves while zoomed — theirs: " + moves(zoomedTheirs).map { String(format: "%.1f", $0) }.joined(separator: " "))
        print("Camera moves while zoomed — Softcut:  " + moves(zoomedOurs).map { String(format: "%.1f", $0) }.joined(separator: " "))
        print("Furthest apart: " + worst.sorted { $0.1 > $1.1 }.prefix(6).map { String(format: "%.1fs (%.2f)", $0.0, $0.1) }.joined(separator: ", "))
        if let from = value(after: "--from", in: args).flatMap(Double.init), let to = value(after: "--to", in: args).flatMap(Double.init) {
            for sample in theirs where sample.t >= from && sample.t <= to {
                let ours = plan.camera(at: sample.t)
                print(String(format: "%5.1f  theirs %.2f %.3f %.3f   softcut %.2f %.3f %.3f", sample.t, sample.s, sample.x, sample.y, ours.scale, ours.centerX, ours.centerY))
            }
        }

    case "trace-cursor":
        // softcut-cli trace-cursor FINISHED.mp4 FOLDER TRACE.csv [-o OUT.csv]: where another app drew the cursor, next to
        // the real mouse and Softcut's cursor, using that app's camera from trace-camera.
        guard args.count >= 4 else { fail(usage) }
        let bundle = try RecordingBundle.load(from: URL(fileURLWithPath: args[2]))
        let cameras: [(t: Double, s: Double, x: Double, y: Double)] = try String(contentsOfFile: args[3], encoding: .utf8)
            .split(separator: "\n").dropFirst().compactMap { line in
                let v = line.split(separator: ",").compactMap { Double($0) }
                return v.count >= 5 && v[4] < 9 ? (v[0], v[1], v[2], v[3]) : nil
            }
        let samples = try await CursorTrace.run(finishedURL: URL(fileURLWithPath: args[1]), rawURL: bundle.videoURL,
                                                cameras: cameras, moves: bundle.input.moves)
        let plan = AutoEditor.makePlan(for: bundle, project: EditProject.auto(for: bundle))
        var csv = "t,their_x,their_y,pixels,mouse_x,mouse_y,softcut_x,softcut_y\n"
        var moveIndex = 0
        for sample in samples {
            while moveIndex < bundle.input.moves.count, bundle.input.moves[moveIndex].t <= sample.t { moveIndex += 1 }
            let mouse = bundle.input.moves[max(0, moveIndex - 1)]
            let ours = plan.cursor(at: sample.t)
            csv += String(format: "%.3f,%.4f,%.4f,%d,%.4f,%.4f,%.4f,%.4f\n", sample.t, sample.x, sample.y, sample.pixels, mouse.x, mouse.y, ours.x, ours.y)
        }
        let output = value(after: "-o", in: args) ?? bundle.folder.appendingPathComponent("cursor-trace.csv").path
        try csv.write(toFile: output, atomically: true, encoding: .utf8)
        print("Wrote \(samples.count) samples to \(output)")

    case "cursor-path":
        // softcut-cli cursor-path FOLDER FROM TO OUT.png: draw the real mouse path (thin red) and the cursor's path (green).
        guard args.count >= 5, let from = Double(args[2]), let to = Double(args[3]) else { fail(usage) }
        let bundle = try RecordingBundle.load(from: URL(fileURLWithPath: args[1]))
        let plan = AutoEditor.makePlan(for: bundle, project: EditProject.auto(for: bundle))
        let width = 1400.0, height = width * bundle.manifest.displayHeight / bundle.manifest.displayWidth
        guard let ctx = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fail("no context") }
        ctx.setFillColor(CGColor(gray: 0.08, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * width, y: (1 - y) * height) }
        let moves = bundle.input.moves.filter { $0.t >= from && $0.t <= to }
        ctx.setStrokeColor(CGColor(red: 1, green: 0.3, blue: 0.3, alpha: 0.9)); ctx.setLineWidth(1.5)
        for (i, m) in moves.enumerated() { if i == 0 { ctx.move(to: point(m.x, m.y)) } else { ctx.addLine(to: point(m.x, m.y)) } }
        ctx.strokePath()
        ctx.setStrokeColor(CGColor(red: 0.3, green: 1, blue: 0.5, alpha: 0.9)); ctx.setLineWidth(3)
        var t = from, first = true
        while t <= to {
            let c = plan.cursor(at: t)
            if first { ctx.move(to: point(c.x, c.y)); first = false } else { ctx.addLine(to: point(c.x, c.y)) }
            t += 1.0 / 120
        }
        ctx.strokePath()
        // Dots every 50 ms on the cursor path show its pace: close together is slow, far apart is fast.
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.9))
        t = from
        while t <= to { let c = point(plan.cursor(at: t).x, plan.cursor(at: t).y); ctx.fillEllipse(in: CGRect(x: c.x - 2.5, y: c.y - 2.5, width: 5, height: 5)); t += 0.05 }
        for click in bundle.input.clicks where click.down && click.t >= from && click.t <= to {
            let c = point(click.x, click.y)
            ctx.setStrokeColor(CGColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)); ctx.setLineWidth(2)
            ctx.strokeEllipse(in: CGRect(x: c.x - 9, y: c.y - 9, width: 18, height: 18))
        }
        guard let image = ctx.makeImage(),
              let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[4]) as CFURL, UTType.png.identifier as CFString, 1, nil) else { fail("no image") }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        print("Wrote \(args[4])")

    case "result-snapshot":
        // softcut-cli result-snapshot FOLDER OUT.png: draw the window shown when a recording stops.
        guard args.count >= 3 else { fail(usage) }
        _ = NSApplication.shared
        let rep = try await ResultSnapshot.render(folder: URL(fileURLWithPath: args[1]), size: CGSize(width: 1120, height: 780))
        guard let png = rep.representation(using: .png, properties: [:]) else { fail("Could not make a picture") }
        try png.write(to: URL(fileURLWithPath: args[2]))
        print("Wrote \(args[2])")

    case "check":
        // softcut-cli check FOLDER: how watchable the recording's edit is, and how it compares with Screen Studio's if imported.
        guard args.count >= 2 else { fail(usage) }
        let bundle = try RecordingBundle.load(from: URL(fileURLWithPath: args[1]))
        let project = args.contains("--fresh") ? EditProject.auto(for: bundle) : EditProject.open(bundle)
        let plan = AutoEditor.makePlan(for: bundle, project: project)
        print(EditQuality.measure(plan: plan, bundle: bundle))
        let referenceFile = bundle.folder.appendingPathComponent("screenstudio-zooms.json")
        if let data = try? Data(contentsOf: referenceFile),
           let reference = try? JSONDecoder().decode([ScreenStudioImport.ReferenceZoom].self, from: data) {
            print("Screen Studio zooms: " + reference.map { String(format: "%.2f–%.2f", $0.start, $0.end) }.joined(separator: ", "))
            print("Softcut zooms:         " + project.zooms.map { String(format: "%.2f–%.2f", $0.start, $0.end) }.joined(separator: ", "))
        }

    case "click-timing":
        // softcut-cli click-timing FOLDER: when the mouse, cursor and picture act around each click.
        guard args.count >= 2 else { fail(usage) }
        if let seconds = value(after: "--live", in: args).flatMap(Double.init) {
            try await ClickTiming.live(folder: URL(fileURLWithPath: args[1]), seconds: seconds, startAt: value(after: "--from", in: args).flatMap(Double.init) ?? 0)
        } else if let work = value(after: "--sync", in: args) {
            try await ClickTiming.sync(folder: URL(fileURLWithPath: args[1]), work: URL(fileURLWithPath: work))
        } else {
            try await ClickTiming.run(folder: URL(fileURLWithPath: args[1]))
        }

    case "import-screenstudio":
        // softcut-cli import-screenstudio PROJECT.screenstudio OUTFOLDER: make a Softcut recording from a Screen Studio project.
        guard args.count >= 3 else { fail(usage) }
        let bundle = try await ScreenStudioImport.importProject(at: URL(fileURLWithPath: args[1]), to: URL(fileURLWithPath: args[2]))
        try EditProject.auto(for: bundle).save(to: bundle.folder)
        let reference = try ScreenStudioImport.referenceZooms(URL(fileURLWithPath: args[1]))
        print(String(format: "Imported %.1fs, %d moves, %d clicks; Screen Studio made %d zoom(s)", bundle.manifest.duration,
                     bundle.input.moves.count, bundle.input.clicks.filter(\.down).count, reference.count))

    case "frames":
        // softcut-cli frames VIDEO OUTFOLDER T1 T2 ...: save still frames for inspection.
        guard args.count >= 4 else { fail(usage) }
        let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))
        let folder = URL(fileURLWithPath: args[2])
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        for text in args[3...] {
            guard let seconds = Double(text) else { continue }
            let image = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
            let url = folder.appendingPathComponent(String(format: "frame-%06.2f.png", seconds))
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
            print("Wrote \(url.path) (\(image.width)x\(image.height))")
        }

    case "record":
        _ = NSApplication.shared
        guard RecordingSession.hasScreenRecordingPermission() else {
            RecordingSession.requestScreenRecordingPermission()
            fail("Screen Recording permission is needed. Allow your terminal in System Settings > Privacy & Security > Screen Recording, then run this again.")
        }
        let seconds = value(after: "--seconds", in: args).flatMap(Double.init) ?? 10
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let folder = value(after: "-o", in: args).map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Softcut \(stamp)")
        let webcam = args.contains("--webcam")
        let typing = args.contains("--typing")
        if webcam, !(await CameraAccess.request()) {
            fail("Camera access was not granted. Allow your terminal in System Settings > Privacy & Security > Camera.")
        }
        if typing {
            if !InputRecorder.hasKeyboardAccess { InputRecorder.requestKeyboardAccess() }
            if !InputRecorder.hasAccessibilityAccess { InputRecorder.requestAccessibilityAccess() }
        }
        let session = RecordingSession(options: RecordingOptions(
            systemAudio: args.contains("--system-audio"), microphone: args.contains("--mic"), webcam: webcam,
            captureKeys: typing, trackCaret: typing, outputFolder: folder))
        try await session.start()
        print("Recording for \(Int(seconds)) seconds…")
        try await Task.sleep(for: .seconds(seconds))
        let bundle = try await session.stop()
        try await render(bundle, to: folder.deletingLastPathComponent().appendingPathComponent(folder.lastPathComponent + ".mp4"),
                         settings: editSettings(from: args))

    default:
        print(usage)
    }
} catch {
    fail("Error: \(error.localizedDescription)\n\(error)")
}
