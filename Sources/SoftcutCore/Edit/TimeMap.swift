import Foundation

/// One stretch of a recording that appears in the video, played at `speed`. The video is these clips
/// one after another, in the order they are listed, which need not be the order they were recorded in.
public struct TimeSegment: Equatable, Codable, Identifiable, Sendable {
    public var id: UUID
    /// Which recording the clip comes from. Nil is the project's own recording; otherwise an attached one.
    public var sourceID: UUID?
    public var sourceStart: Double
    public var sourceEnd: Double
    public var speed: Double
    /// Leave the cursor out of this stretch of the video.
    public var hideCursor: Bool

    public init(id: UUID = UUID(), sourceID: UUID? = nil, sourceStart: Double, sourceEnd: Double, speed: Double = 1, hideCursor: Bool = false) {
        self.hideCursor = hideCursor
        self.sourceID = sourceID
        self.id = id
        self.sourceStart = sourceStart
        self.sourceEnd = sourceEnd
        self.speed = speed
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        sourceID = c.value(.sourceID, nil)
        sourceStart = try c.decode(Double.self, forKey: .sourceStart)
        sourceEnd = try c.decode(Double.self, forKey: .sourceEnd)
        speed = c.value(.speed, 1)
        hideCursor = c.value(.hideCursor, false)
    }

    public var sourceDuration: Double { sourceEnd - sourceStart }
    public var outputDuration: Double { sourceDuration / speed }
}

/// Maps the video's time to the recordings it is made of. The video is the clips end to end, in list order,
/// so cutting, trimming, reordering and speeding up are all expressed as the list of clips.
public struct TimeMap: Equatable, Sendable {
    public let segments: [TimeSegment]
    public let outputDuration: Double

    public init(segments: [TimeSegment]) {
        let usable = segments.filter { $0.sourceDuration > 0.001 }
        self.segments = usable
        self.outputDuration = usable.reduce(0) { $0 + $1.outputDuration }
    }

    public static func identity(duration: Double) -> TimeMap {
        TimeMap(segments: [TimeSegment(sourceStart: 0, sourceEnd: duration)])
    }

    /// Where a moment of the video comes from.
    public struct Location: Sendable {
        public let index: Int
        public let segment: TimeSegment
        /// The moment in the clip's recording, in that recording's own seconds.
        public let sourceTime: Double
        /// When the clip starts in the video.
        public let outputStart: Double
    }

    public func locate(output time: Double) -> Location? {
        guard let last = segments.last else { return nil }
        var start = 0.0
        for (index, segment) in segments.enumerated() {
            let length = segment.outputDuration
            if time < start + length || index == segments.count - 1 {
                let within = min(max(0, time - start), length)
                return Location(index: index, segment: segment, sourceTime: segment.sourceStart + within * segment.speed, outputStart: start)
            }
            start += length
        }
        return Location(index: segments.count - 1, segment: last, sourceTime: last.sourceEnd, outputStart: outputDuration - last.outputDuration)
    }

    public func sourceTime(forOutput time: Double) -> Double {
        locate(output: time)?.sourceTime ?? 0
    }

    /// When a moment of a recording appears in the video. A moment that was cut out maps to where the next
    /// stretch of that recording begins, so a playhead dropped on a cut lands on the next picture.
    public func outputTime(forSource time: Double, source: UUID? = nil) -> Double {
        var start = 0.0
        var nextStart: Double?
        for segment in segments {
            if segment.sourceID == source {
                if time >= segment.sourceStart, time <= segment.sourceEnd {
                    return start + (time - segment.sourceStart) / segment.speed
                }
                if time < segment.sourceStart { nextStart = min(nextStart ?? start, start) }
            }
            start += segment.outputDuration
        }
        return nextStart ?? outputDuration
    }

    /// The clip a moment of a recording falls in, if it is in the video.
    public func segment(atSource time: Double, source: UUID? = nil) -> TimeSegment? {
        segments.first { $0.sourceID == source && time >= $0.sourceStart && time <= $0.sourceEnd }
    }

    /// Whether a moment of a recording appears in the video.
    public func keeps(_ time: Double, source: UUID? = nil) -> Bool {
        segment(atSource: time, source: source) != nil
    }

    /// When each clip starts in the video.
    public var outputStarts: [Double] {
        var start = 0.0
        return segments.map { segment in
            defer { start += segment.outputDuration }
            return start
        }
    }

    /// A stretch of a recording as it appears in the video. A range that spans cuts, or that is used by
    /// several clips, appears in more than one place.
    public struct Piece: Equatable, Sendable {
        public let segmentIndex: Int
        public let outputStart: Double
        public let outputEnd: Double
        public let sourceStart: Double
        public let sourceEnd: Double
    }

    public func pieces(source: UUID?, sourceStart: Double, sourceEnd: Double) -> [Piece] {
        var result: [Piece] = []
        var start = 0.0
        for (index, segment) in segments.enumerated() {
            defer { start += segment.outputDuration }
            guard segment.sourceID == source else { continue }
            let low = max(sourceStart, segment.sourceStart)
            let high = min(sourceEnd, segment.sourceEnd)
            guard high - low > 0.0001 else { continue }
            result.append(Piece(segmentIndex: index,
                                outputStart: start + (low - segment.sourceStart) / segment.speed,
                                outputEnd: start + (high - segment.sourceStart) / segment.speed,
                                sourceStart: low, sourceEnd: high))
        }
        return result
    }
}
