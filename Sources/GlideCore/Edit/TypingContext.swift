import Foundation

/// Answers "is someone typing at this moment, and where is the caret?" from the recorded
/// key times and caret samples.
struct TypingContext {
    /// A key press this long ago still counts as typing.
    static let lingerAfter = 1.5
    /// A key press this far ahead counts too, so the camera is already on the caret as typing starts.
    static let lookAhead = 0.2

    private let keyTimes: [Double]
    private let focus: [FocusSample]

    init(keys: [KeyEvent] = [], focus: [FocusSample] = []) {
        keyTimes = keys.filter { !$0.shortcut }.map(\.t).sorted()
        self.focus = focus.sorted { $0.t < $1.t }
    }

    func isTyping(at time: Double) -> Bool {
        // First key at or after the start of the window; typing if it is not past the end of it.
        let windowStart = time - Self.lingerAfter
        var low = 0
        var high = keyTimes.count
        while low < high {
            let mid = (low + high) / 2
            if keyTimes[mid] < windowStart { low = mid + 1 } else { high = mid }
        }
        return low < keyTimes.count && keyTimes[low] <= time + Self.lookAhead
    }

    /// The caret position, or nil when nobody is typing or no caret was recorded recently.
    func caret(at time: Double) -> SIMD2<Double>? {
        guard isTyping(at: time) else { return nil }
        var low = 0
        var high = focus.count
        while low < high {
            let mid = (low + high) / 2
            if focus[mid].t <= time + 0.1 { low = mid + 1 } else { high = mid }
        }
        guard low > 0 else { return focus.first.flatMap { $0.t - time < 1 ? SIMD2($0.x, $0.y) : nil } }
        let sample = focus[low - 1]
        guard time - sample.t <= Self.lingerAfter else { return nil }
        return SIMD2(sample.x, sample.y)
    }
}
