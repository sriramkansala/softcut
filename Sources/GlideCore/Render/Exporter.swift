import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

final class GlideInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let trackID: CMPersistentTrackID
    let webcamTrackID: CMPersistentTrackID?
    let renderer: FrameRenderer

    init(timeRange: CMTimeRange, trackID: CMPersistentTrackID, webcamTrackID: CMPersistentTrackID? = nil, renderer: FrameRenderer) {
        self.timeRange = timeRange
        self.trackID = trackID
        self.webcamTrackID = webcamTrackID
        self.renderer = renderer
        self.requiredSourceTrackIDs = ([trackID] + (webcamTrackID.map { [$0] } ?? [])).map { NSNumber(value: $0) }
    }
}

final class GlideCompositor: NSObject, AVVideoCompositing {
    private static let attributes: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferMetalCompatibilityKey as String: true,
    ]
    var sourcePixelBufferAttributes: [String: any Sendable]? { Self.attributes }
    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] { Self.attributes }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? GlideInstruction,
              let source = request.sourceFrame(byTrackID: instruction.trackID),
              let output = request.renderContext.newPixelBuffer() else {
            request.finish(with: GlideError.writerFailed("could not get a frame to render"))
            return
        }
        // Nil while the webcam has not started yet or has already ended.
        let webcam = instruction.webcamTrackID.flatMap { request.sourceFrame(byTrackID: $0) }
        instruction.renderer.render(source: source, webcam: webcam, outputTime: request.compositionTime.seconds, into: output)
        request.finish(withComposedVideoFrame: output)
    }

    func cancelAllPendingVideoCompositionRequests() {}
}

enum WebcamTiming {
    struct Slice: Equatable {
        /// Range to take from the webcam file.
        var sourceStart: Double
        var sourceEnd: Double
        /// Seconds after the start of the screen segment at which the webcam picture begins.
        var delay: Double
    }

    /// Where a stretch of the screen recording `screenStart..<screenEnd` falls in the webcam file.
    /// Webcam time = screen time - offset. Returns nil when the webcam has nothing for that stretch,
    /// which happens when it started late or ended early.
    static func slice(screenStart: Double, screenEnd: Double, offset: Double, webcamDuration: Double) -> Slice? {
        let start = screenStart - offset
        let end = screenEnd - offset
        let sourceStart = max(0, start)
        let sourceEnd = min(end, webcamDuration)
        guard sourceEnd - sourceStart > 0.001 else { return nil }
        return Slice(sourceStart: sourceStart, sourceEnd: sourceEnd, delay: max(0, -start))
    }
}

enum AudioRole: Equatable { case system, microphone, music, clicks, voiceOver(UUID) }

/// Everything AVFoundation needs to play or export a plan.
struct BuiltComposition {
    let composition: AVMutableComposition
    let videoComposition: AVMutableVideoComposition
    let audioMix: AVMutableAudioMix?
    let audioTracks: [(role: AudioRole, track: AVMutableCompositionTrack)]
    let renderer: FrameRenderer
    /// Kept so the assets outlive the tracks taken from them.
    let assets: [AVAsset]
}

enum CompositionBuilder {
    /// One recording opened for use: its picture, its sound, and its webcam if it has one.
    private struct Media {
        let asset: AVURLAsset
        let video: AVAssetTrack
        let audio: [(role: AudioRole, track: AVAssetTrack)]
        let duration: Double
        var webcam: (asset: AVURLAsset, track: AVAssetTrack, duration: Double, offset: Double)?
    }

    private static func open(_ bundle: RecordingBundle, wantsWebcam: Bool) async throws -> Media {
        let asset = AVURLAsset(url: bundle.videoURL)
        guard let video = try await asset.loadTracks(withMediaType: .video).first else { throw GlideError.noVideoTrack }
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let duration = try await asset.load(.duration).seconds

        // Which audio track is which. The recorder writes system audio first, then the microphone.
        var roles: [AudioRole] = []
        if bundle.manifest.hasSystemAudio { roles.append(.system) }
        if bundle.manifest.hasMicrophone { roles.append(.microphone) }
        if roles.count != audioTracks.count { roles = Array(repeating: .microphone, count: audioTracks.count) }

        var media = Media(asset: asset, video: video, audio: Array(zip(roles, audioTracks)).map { (role: $0.0, track: $0.1) }, duration: duration)
        // The webcam is its own file. A broken or empty one must not stop the screen from rendering.
        if wantsWebcam, let url = bundle.webcamURL, let offset = bundle.manifest.webcamOffset {
            let webcamAsset = AVURLAsset(url: url)
            if let track = try? await webcamAsset.loadTracks(withMediaType: .video).first,
               let webcamDuration = try? await webcamAsset.load(.duration).seconds {
                media.webcam = (webcamAsset, track, webcamDuration, offset)
            }
        }
        return media
    }

    static func build(sources: SourceSet, plan: EditPlan) async throws -> BuiltComposition {
        // Open each recording the video uses, once.
        var medias: [UUID?: Media] = [:]
        var order: [UUID?] = [nil]
        for segment in plan.timeMap.segments where !order.contains(where: { $0 == segment.sourceID }) { order.append(segment.sourceID) }
        for id in order {
            guard let bundle = sources.bundle(id) else { continue }
            medias[id] = try await open(bundle, wantsWebcam: plan.settings.style.showWebcam)
        }
        guard medias[nil] != nil else { throw GlideError.noVideoTrack }

        let composition = AVMutableComposition()
        guard let compositionVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw GlideError.noVideoTrack
        }
        // One webcam track if any recording has a webcam, and one audio track for each kind of sound.
        let webcamTarget = medias.values.contains { $0.webcam != nil }
            ? composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) : nil
        var audioTargets: [(role: AudioRole, track: AVMutableCompositionTrack)] = []
        func audioTarget(for role: AudioRole) -> AVMutableCompositionTrack? {
            if let existing = audioTargets.first(where: { $0.role == role }) { return existing.track }
            guard let created = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }
            audioTargets.append((role, created))
            return created
        }

        func time(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 60_000) }
        var cursor = CMTime.zero
        for segment in plan.timeMap.segments {
            guard let media = medias[segment.sourceID] else { continue }
            let start = min(segment.sourceStart, media.duration)
            let end = min(segment.sourceEnd, media.duration)
            guard end > start else { continue }
            let range = CMTimeRange(start: time(start), end: time(end))
            try compositionVideo.insertTimeRange(range, of: media.video, at: cursor)
            for (role, track) in media.audio {
                if let target = audioTarget(for: role) { try target.insertTimeRange(range, of: track, at: cursor) }
            }
            if let webcam = media.webcam, let target = webcamTarget,
               let slice = WebcamTiming.slice(screenStart: start, screenEnd: end, offset: webcam.offset, webcamDuration: webcam.duration) {
                try target.insertTimeRange(CMTimeRange(start: time(slice.sourceStart), end: time(slice.sourceEnd)),
                                           of: webcam.track, at: cursor + time(slice.delay))
            }
            let outputDuration = time((end - start) / segment.speed)
            if segment.speed != 1 {
                composition.scaleTimeRange(CMTimeRange(start: cursor, duration: range.duration), toDuration: outputDuration)
            }
            cursor = cursor + outputDuration
        }
        guard cursor > .zero else { throw GlideError.noFramesCaptured }
        let extraAssets = await addExtraAudio(to: composition, plan: plan, total: cursor, into: &audioTargets)

        let renderer = FrameRenderer(sources: sources, plan: plan)
        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = GlideCompositor.self
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(plan.settings.style.fps))
        videoComposition.renderSize = renderer.canvasSize
        videoComposition.instructions = [
            GlideInstruction(timeRange: CMTimeRange(start: .zero, duration: composition.duration),
                             trackID: compositionVideo.trackID, webcamTrackID: webcamTarget?.trackID, renderer: renderer),
        ]

        // The assets are kept: an AVAssetTrack does not keep its asset alive, and inserting from a track
        // whose asset has been freed fails with an unhelpful CoreMedia error.
        let assets = medias.values.flatMap { [$0.asset] + ($0.webcam.map { [$0.asset] } ?? []) as [AVAsset] } + extraAssets
        return BuiltComposition(composition: composition, videoComposition: videoComposition,
                                audioMix: audioMix(tracks: audioTargets, settings: plan.audio, duration: cursor.seconds), audioTracks: audioTargets,
                                renderer: renderer, assets: assets)
    }

    static func audioMix(tracks: [(role: AudioRole, track: AVMutableCompositionTrack)], settings: AudioSettings, duration: Double) -> AVMutableAudioMix? {
        guard !tracks.isEmpty else { return nil }
        let master = Float(settings.volume)
        let mix = AVMutableAudioMix()
        mix.inputParameters = tracks.map { role, track in
            let parameters = AVMutableAudioMixInputParameters(track: track)
            switch role {
            case .microphone:
                parameters.setVolume(settings.muteMicrophone ? 0 : master, at: .zero)
            case .system:
                parameters.setVolume(settings.muteSystemAudio ? 0 : master, at: .zero)
            case .clicks:
                parameters.setVolume(master * Float(settings.clickVolume), at: .zero)
            case .voiceOver(let id):
                let gain = settings.voiceOvers.first { $0.id == id }?.volume ?? 1
                parameters.setVolume(master * Float(gain), at: .zero)
            case .music:
                // Eased in and out, so it does not start or stop with a jolt.
                let level = master * Float(settings.music?.volume ?? 0.3)
                let fade = min(2.0, duration / 4)
                if duration > 1 {
                    parameters.setVolumeRamp(fromStartVolume: 0, toEndVolume: level, timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 0.5, preferredTimescale: 600)))
                    parameters.setVolumeRamp(fromStartVolume: level, toEndVolume: 0,
                                             timeRange: CMTimeRange(start: CMTime(seconds: duration - fade, preferredTimescale: 600), duration: CMTime(seconds: fade, preferredTimescale: 600)))
                } else {
                    parameters.setVolume(level, at: .zero)
                }
            }
            return parameters
        }
        return mix
    }
}

public enum ExportCodec: String, Codable, CaseIterable, Sendable {
    case h264, hevc

    public var title: String { self == .h264 ? "H.264 (most compatible)" : "HEVC (smaller files)" }
}

public enum Exporter {
    /// Renders a single recording. Recordings attached to a project are not included; use the `SourceSet` version for those.
    public static func export(bundle: RecordingBundle, plan: EditPlan, to outputURL: URL, codec: ExportCodec = .h264,
                              progress: (@Sendable (Double) -> Void)? = nil) async throws {
        try await export(sources: SourceSet(primary: bundle), plan: plan, to: outputURL, codec: codec, progress: progress)
    }

    public static func exportGIF(bundle: RecordingBundle, plan: EditPlan, to outputURL: URL, width: Int, fps: Int,
                                 progress: (@Sendable (Double) -> Void)? = nil) async throws {
        try await exportGIF(sources: SourceSet(primary: bundle), plan: plan, to: outputURL, width: width, fps: fps, progress: progress)
    }

    /// Renders the edit as an animated GIF at a smaller size and a lower frame rate than a video.
    public static func exportGIF(sources: SourceSet, plan: EditPlan, to outputURL: URL, width: Int, fps: Int,
                                 progress: (@Sendable (Double) -> Void)? = nil) async throws {
        var plan = plan
        plan.settings.style.maxOutputWidth = width
        let built = try await CompositionBuilder.build(sources: sources, plan: plan)
        let duration = built.composition.duration.seconds
        let frameCount = max(1, Int(duration * Double(fps)))

        try? FileManager.default.removeItem(at: outputURL)
        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else {
            throw GlideError.writerFailed("could not create the GIF file")
        }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]] as CFDictionary)

        let generator = AVAssetImageGenerator(asset: built.composition)
        generator.videoComposition = built.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let frameProperties = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: 1.0 / Double(fps)]] as CFDictionary

        for index in 0..<frameCount {
            let time = CMTime(seconds: min(Double(index) / Double(fps), max(0, duration - 0.02)), preferredTimescale: 600)
            let frame = try await generator.image(at: time).image
            CGImageDestinationAddImage(destination, frame, frameProperties)
            progress?(Double(index + 1) / Double(frameCount))
        }
        guard CGImageDestinationFinalize(destination) else { throw GlideError.writerFailed("could not write the GIF file") }
        withExtendedLifetime(built) {}
    }

    /// How many bits go to each pixel of each frame. Apple's export presets pick far less than screen content needs: small
    /// text and fast 3D moves turn soft. HEVC needs about 60% of what H.264 does for the same look.
    static func bitRate(canvas: CGSize, fps: Int, codec: ExportCodec) -> Int {
        let bitsPerPixel = codec == .hevc ? 0.11 : 0.18
        return Int(canvas.width * canvas.height * Double(max(fps, 1)) * bitsPerPixel)
    }

    /// Renders the edited video. `progress` is called with 0...1 while exporting.
    public static func export(sources: SourceSet, plan: EditPlan, to outputURL: URL, codec: ExportCodec = .h264,
                              progress: (@Sendable (Double) -> Void)? = nil) async throws {
        let built = try await CompositionBuilder.build(sources: sources, plan: plan)
        let composition = built.composition
        let duration = composition.duration.seconds
        let style = plan.settings.style
        let canvas = built.videoComposition.renderSize

        let reader = try AVAssetReader(asset: composition)
        let videoTracks = try await composition.loadTracks(withMediaType: .video)
        let frames = AVAssetReaderVideoCompositionOutput(videoTracks: videoTracks, videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ])
        frames.videoComposition = built.videoComposition
        frames.alwaysCopiesSampleData = false
        guard reader.canAdd(frames) else { throw GlideError.writerFailed("could not read the video") }
        reader.add(frames)

        let audioTracks = try await composition.loadTracks(withMediaType: .audio)
        var sound: AVAssetReaderAudioMixOutput?
        if !audioTracks.isEmpty {
            let output = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
            ])
            output.audioMix = built.audioMix
            guard reader.canAdd(output) else { throw GlideError.writerFailed("could not read the sound") }
            reader.add(output)
            sound = output
        }

        try? FileManager.default.removeItem(at: outputURL)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        // That leaves the unoptimized copy beside the finished file, as "<name>.sb-<random>".
        defer { removeLeftovers(of: outputURL) }
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: bitRate(canvas: canvas, fps: style.fps, codec: codec),
            AVVideoExpectedSourceFrameRateKey: style.fps,
            AVVideoMaxKeyFrameIntervalKey: style.fps * 2,
        ]
        if codec == .h264 {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
            compression[AVVideoH264EntropyModeKey] = AVVideoH264EntropyModeCABAC
        }
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec == .hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: Int(canvas.width), AVVideoHeightKey: Int(canvas.height),
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: compression,
        ])
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else { throw GlideError.writerFailed("could not write the video") }
        writer.add(videoInput)
        var audioInput: AVAssetWriterInput?
        if sound != nil {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 256_000,
            ])
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else { throw GlideError.writerFailed("could not write the sound") }
            writer.add(input)
            audioInput = input
        }

        guard reader.startReading() else { throw reader.error ?? GlideError.writerFailed("could not read the video") }
        guard writer.startWriting() else { throw writer.error ?? GlideError.writerFailed("could not write the video") }
        writer.startSession(atSourceTime: .zero)

        // Each track feeds the writer whenever it has room. The first failure stops everything.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let run = ExportRun(tracks: sound == nil ? 1 : 2, reader: reader, writer: writer, continuation: continuation)
            run.pump(frames, into: videoInput, queue: "glide.export.video") { time in
                if duration > 0 { progress?(min(1, time / duration)) }
            }
            if let sound, let audioInput {
                run.pump(sound, into: audioInput, queue: "glide.export.audio") { _ in }
            }
        }

        await writer.finishWriting()
        if writer.status != .completed {
            throw writer.error ?? GlideError.writerFailed("could not finish the video")
        }
        progress?(1)
        withExtendedLifetime(built) {}
    }
}

private func removeLeftovers(of outputURL: URL) {
    let folder = outputURL.deletingLastPathComponent()
    let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    for name in names where name.hasPrefix(outputURL.lastPathComponent + ".sb-") {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
    }
}

/// One export in progress: moves each track's samples from the reader to the writer, and ends once, when all of them are
/// done or when the first one fails.
private final class ExportRun: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: Int
    private var continuation: CheckedContinuation<Void, Error>?
    private let reader: AVAssetReader
    private let writer: AVAssetWriter

    init(tracks: Int, reader: AVAssetReader, writer: AVAssetWriter, continuation: CheckedContinuation<Void, Error>) {
        remaining = tracks
        self.reader = reader
        self.writer = writer
        self.continuation = continuation
    }

    func pump(_ output: AVAssetReaderOutput, into input: AVAssetWriterInput, queue label: String, reached: @escaping @Sendable (Double) -> Void) {
        nonisolated(unsafe) let output = output
        nonisolated(unsafe) let input = input
        nonisolated(unsafe) var done = false
        input.requestMediaDataWhenReady(on: DispatchQueue(label: label)) { [self] in
            guard !done else { return }
            while input.isReadyForMoreMediaData {
                guard reader.status == .reading, let sample = output.copyNextSampleBuffer() else {
                    done = true
                    if reader.status == .failed || reader.status == .cancelled {
                        finish(failure: reader.error ?? GlideError.writerFailed("could not read the video"))
                    } else {
                        input.markAsFinished()
                        finish(failure: nil)
                    }
                    return
                }
                guard input.append(sample) else {
                    done = true
                    finish(failure: writer.error ?? GlideError.writerFailed("could not write the video"))
                    return
                }
                reached(CMSampleBufferGetPresentationTimeStamp(sample).seconds)
            }
        }
    }

    private func finish(failure: Error?) {
        lock.lock()
        remaining -= 1
        let waiting = continuation
        let isOver = failure != nil || remaining == 0
        if isOver { continuation = nil }
        lock.unlock()
        guard isOver, let waiting else { return }
        if let failure {
            reader.cancelReading()
            writer.cancelWriting()
            waiting.resume(throwing: failure)
        } else {
            waiting.resume()
        }
    }
}

/// A playable preview of a project that can follow edits while it plays.
///
/// Changes to looks (colors, sizes, zoom, cursor, volume) are applied in place, so sliders update the
/// picture immediately. Changes to the shape of the video (cuts, speed, canvas size, webcam on or off)
/// need a new session, and `update` says so by returning false.
@MainActor
public final class PreviewSession: @unchecked Sendable {
    /// An edit worked out and ready to show.
    public struct Update: @unchecked Sendable {
        fileprivate let look: FrameRenderer.Look
        fileprivate let audio: AudioSettings
    }

    public let item: AVPlayerItem
    /// Length of the output video in seconds.
    public private(set) var duration: Double
    public private(set) var canvasSize: CGSize

    private let built: BuiltComposition
    private let sources: SourceSet
    private let previewWidth: Int
    /// Whether the preview's width follows the project, or was asked for.
    private let automaticWidth: Bool
    private let timeMap: TimeMap
    private let showsWebcam: Bool
    private let audioStructure: AudioStructure
    private var audio: AudioSettings

    /// An automatic width is really the longest side: a tall video previewed at that width would be thousands of pixels high.
    private static func previewPlan(_ project: EditProject, sources: SourceSet, width: Int, automatic: Bool) -> EditPlan {
        var project = project
        project.settings.style.maxOutputWidth = width
        guard automatic else { return AutoEditor.makePlan(sources: sources, project: project) }
        let primary = sources.primary.manifest
        let style = project.settings.style
        let canvas = FrameRenderer.layout(displayWidth: primary.displayWidth, displayHeight: primary.displayHeight, style: style,
                                          hasCamera: FrameRenderer.usesCameraPanel(style, hasWebcam: sources.hasWebcam)).canvas
        if canvas.height > canvas.width {
            project.settings.style.maxOutputWidth = Int((Double(width) * canvas.width / canvas.height / 2).rounded()) * 2
        }
        return AutoEditor.makePlan(sources: sources, project: project)
    }

    /// A 3D device has fine detail and its screen takes up only part of the picture, so it needs more pixels to preview well.
    private static func previewWidth(for project: EditProject) -> Int {
        project.settings.style.mockup == nil ? 1280 : 1920
    }

    public static func make(bundle: RecordingBundle, project: EditProject, previewWidth: Int? = nil) async throws -> PreviewSession {
        try await make(sources: SourceSet.load(primary: bundle, project: project), project: project, previewWidth: previewWidth)
    }

    public static func make(sources: SourceSet, project: EditProject, previewWidth: Int? = nil) async throws -> PreviewSession {
        let automaticWidth = previewWidth == nil
        let previewWidth = previewWidth ?? Self.previewWidth(for: project)
        let plan = previewPlan(project, sources: sources, width: previewWidth, automatic: automaticWidth)
        let built = try await CompositionBuilder.build(sources: sources, plan: plan)
        built.renderer.isPreview = true
        let item = AVPlayerItem(asset: built.composition)
        item.videoComposition = built.videoComposition
        item.audioMix = built.audioMix
        return PreviewSession(item: item, built: built, sources: sources, plan: plan, previewWidth: previewWidth, automaticWidth: automaticWidth)
    }

    private init(item: AVPlayerItem, built: BuiltComposition, sources: SourceSet, plan: EditPlan, previewWidth: Int, automaticWidth: Bool) {
        self.automaticWidth = automaticWidth
        self.item = item
        self.built = built
        self.sources = sources
        self.previewWidth = previewWidth
        self.timeMap = plan.timeMap
        self.duration = plan.outputDuration
        self.canvasSize = built.renderer.canvasSize
        self.showsWebcam = plan.settings.style.showWebcam
        self.audioStructure = plan.audio.structure
        self.audio = plan.audio
    }

    /// Works out an edited project, which can take a while, so this can run away from the main thread. Returns nil when
    /// the media itself changes (cuts, order, speed, the webcam or the recordings) and the preview has to be built again.
    /// Everything else, including the shape and size of the canvas, applies in place.
    public func prepare(project: EditProject) -> Update? {
        // Recordings that were added since this session was made need a new session to be played.
        guard sources.covers(project) else { return nil }
        // A device needs more pixels to preview well than the plain picture does.
        let width = automaticWidth ? Self.previewWidth(for: project) : previewWidth
        let plan = Self.previewPlan(project, sources: sources, width: width, automatic: automaticWidth)
        guard plan.timeMap == timeMap,
              plan.settings.style.showWebcam == showsWebcam,
              plan.audio.structure == audioStructure else { return nil }
        return Update(look: built.renderer.makeLook(plan: plan), audio: plan.audio)
    }

    /// Shows a worked-out edit. Call it on the main thread. A paused player has to be asked to draw it.
    public func apply(_ update: Update, redrawing: Bool = false) {
        built.renderer.use(update.look)
        let resized = update.look.canvasSize != canvasSize
        if resized {
            canvasSize = update.look.canvasSize
            built.videoComposition.renderSize = canvasSize
        }
        if resized || redrawing { item.videoComposition = built.videoComposition.copy() as? AVVideoComposition }
        if update.audio != audio {
            audio = update.audio
            item.audioMix = CompositionBuilder.audioMix(tracks: built.audioTracks, settings: update.audio, duration: built.composition.duration.seconds)
        }
    }

    /// Applies an edited project. Returns false when the change cannot be applied in place.
    @discardableResult
    public func update(project: EditProject) -> Bool {
        guard let update = prepare(project: project) else { return false }
        apply(update)
        return true
    }

    /// One finished frame, drawn the same way playback and export draw it.
    public func frame(atOutputTime time: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: built.composition)
        generator.videoComposition = built.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let clamped = min(max(0, time), max(0, duration - 0.05))
        return try await generator.image(at: CMTime(seconds: clamped, preferredTimescale: 600)).image
    }
}

public enum OutputGeometry {
    /// The size in pixels of the finished video for a recording and a style.
    public static func size(for bundle: RecordingBundle, style: RenderStyle, hasWebcam: Bool = false) -> CGSize {
        FrameRenderer.layout(displayWidth: bundle.manifest.displayWidth, displayHeight: bundle.manifest.displayHeight, style: style,
                             hasCamera: FrameRenderer.usesCameraPanel(style, hasWebcam: hasWebcam)).canvas
    }
}
