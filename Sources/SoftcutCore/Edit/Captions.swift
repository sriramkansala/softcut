import Foundation

/// A spoken word with when it began and how long it lasted, as a speech recognizer reports it.
public struct SpokenWord: Equatable, Sendable {
    public var text: String
    public var start: Double
    public var duration: Double

    public init(text: String, start: Double, duration: Double) {
        self.text = text
        self.start = start
        self.duration = duration
    }

    var end: Double { start + duration }
}

public enum CaptionBuilder {
    /// Longest a line of captions gets, in characters, before the next word starts a new line.
    public static let maxCharacters = 42
    public static let maxDuration = 5.0
    /// A pause this long ends a line.
    public static let pause = 0.8

    /// Groups words into lines that are comfortable to read: a pause, the end of a sentence, or a full line starts the next one.
    public static func lines(from words: [SpokenWord], source: UUID?) -> [CaptionLine] {
        var lines: [CaptionLine] = []
        var current: [SpokenWord] = []

        func flush() {
            guard let first = current.first, let last = current.last else { return }
            let text = current.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            current = []
            guard !text.isEmpty else { return }
            lines.append(CaptionLine(source: source, start: first.start, end: max(last.end, first.start + CaptionLine.minimumLength), text: text))
        }

        for word in words where !word.text.trimmingCharacters(in: .whitespaces).isEmpty {
            if let last = current.last {
                let length = current.map(\.text).joined(separator: " ").count + 1 + word.text.count
                let endsSentence = ".?!".contains(last.text.last ?? " ") && length >= 18
                if word.start - last.end > pause || length > maxCharacters || word.end - current[0].start > maxDuration || endsSentence {
                    flush()
                }
            }
            current.append(word)
        }
        flush()

        // A line stays up until just before the next begins, but never stretches over a long silence.
        for index in lines.indices.dropLast() {
            let gap = lines[index + 1].start - lines[index].end
            if gap > 0 && gap < pause { lines[index].end = lines[index + 1].start - 0.02 }
        }
        return lines
    }

    /// New text for a line, keeping where it starts and ends.
    public static func text(_ line: CaptionLine, replacedWith text: String) -> CaptionLine {
        var copy = line
        copy.text = text
        return copy
    }
}

public enum SubtitleFile {
    /// The entries of an SRT or WebVTT file, in order. Numbering, cue settings and styling tags are left out.
    public static func parse(_ contents: String) -> [(start: Double, end: Double, text: String)] {
        func seconds(_ stamp: Substring) -> Double? {
            let parts = stamp.replacingOccurrences(of: ",", with: ".").split(separator: ":").map { Double($0) }
            guard (2...3).contains(parts.count), !parts.contains(where: { $0 == nil }) else { return nil }
            return parts.reduce(0) { $0 * 60 + ($1 ?? 0) }
        }
        var entries: [(start: Double, end: Double, text: String)] = []
        let lines = contents.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        var index = 0
        while index < lines.count {
            let parts = lines[index].components(separatedBy: "-->")
            index += 1
            guard parts.count == 2,
                  let startStamp = parts[0].split(whereSeparator: \.isWhitespace).last, let start = seconds(startStamp),
                  let endStamp = parts[1].split(whereSeparator: \.isWhitespace).first, let end = seconds(endStamp), end > start else { continue }
            var text: [String] = []
            while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                text.append(lines[index].replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
                index += 1
            }
            let joined = text.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !joined.isEmpty { entries.append((start, end, joined)) }
        }
        return entries
    }

    /// The captions as an SRT subtitle file, in the finished video's time. A line that spans a cut becomes one entry for each part that remains.
    public static func srt(lines: [CaptionLine], timeMap: TimeMap) -> String {
        var entries: [(start: Double, end: Double, text: String)] = []
        for line in lines where !line.text.isEmpty {
            for piece in timeMap.pieces(source: line.source, sourceStart: line.start, sourceEnd: line.end) where piece.outputEnd - piece.outputStart > 0.05 {
                entries.append((piece.outputStart, piece.outputEnd, line.text))
            }
        }
        entries.sort { $0.start < $1.start }

        func stamp(_ seconds: Double) -> String {
            let total = Int((max(0, seconds) * 1000).rounded())
            return String(format: "%02d:%02d:%02d,%03d", total / 3_600_000, total / 60_000 % 60, total / 1000 % 60, total % 1000)
        }
        return entries.enumerated().map { index, entry in
            "\(index + 1)\n\(stamp(entry.start)) --> \(stamp(entry.end))\n\(entry.text)\n"
        }.joined(separator: "\n")
    }
}
