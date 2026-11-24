import GlideCore
import SwiftUI

/// The Chat tab: a transcript above a composer. It makes edits from plain sentences.
struct ChatPanel: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var chat: EditorChat

    var body: some View {
        VStack(spacing: 0) {
            FluidScrollArea(followsBottom: true) {
                VStack(spacing: 2) {
                    ForEach(chat.messages) { message in
                        FluidChatMessage(from: message.from, text: message.text, time: message.time) {
                            if chat.canUndo(message) {
                                FluidIconButton(systemName: "arrow.uturn.backward", help: "Undo this") { chat.undoLastChange() }
                                    .frame(height: 16)
                            }
                        }
                    }
                }
                .padding(12)
            }
            FluidComposer(text: $chat.draft, placeholder: "Tell Softcut what to change…", suggestions: chat.sent.isEmpty ? EditorChat.suggestions : [],
                          history: chat.sent, onSend: chat.send) {
                Text("Fixed commands, on this Mac")
                    .font(Fluid.font(.caption))
                    .foregroundStyle(Fluid.mutedForeground)
                    .lineLimit(1)
                    .padding(.leading, 6)
            }
            .padding(12)
        }
    }
}

/// The conversation in the Chat tab, and what it understands. Sentences are matched against fixed rules on this Mac:
/// nothing leaves the computer, and there is no AI model behind it, so it says so when it does not follow.
@MainActor
final class EditorChat: ObservableObject {
    struct Message: Identifiable {
        let id = UUID()
        let from: FluidChatSender
        let text: String
        var time: Date?
    }

    static let suggestions = ["Put it in a MacBook Pro 16", "Use the Glacier wallpaper", "Add a zoom here", "What can you do?"]

    private static let greeting = "Tell me what to change and I'll do it: devices, zooms, padding, backgrounds and more. I work from fixed commands on this Mac and I'm not an AI model, so I can't answer open questions."
    private static let notUnderstood = "I didn't understand that. I work from fixed commands, so I can't answer open questions. Say “help” to see what I can do."
    private static let help = """
    You can ask me to:
    • put it in a MacBook or an iPhone, and change how it arrives
    • change the padding, corners, shadow, shape or background
    • add a zoom, split, blur or caption here, or at a time like 0:12
    • turn zooms, captions, the cursor or the sound on and off
    • undo, redo, play, pause, go to a time, or open Export
    """

    @Published private(set) var messages = [Message(from: .assistant, text: EditorChat.greeting)]
    @Published var draft = ""
    /// What was sent, oldest first, for ↑ in the composer.
    private(set) var sent: [String] = []
    /// The latest reply that changed the video, while nothing else has changed it since.
    @Published private var lastChange: (message: UUID, steps: Int, result: EditProject)?
    var showExport: () -> Void = {}

    private let model: EditorModel
    private let library = MockupLibrary.shared

    init(model: EditorModel) {
        self.model = model
    }

    func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sent.append(text)
        let depth = model.undoDepth
        let reply = Message(from: .assistant, text: answer(text))
        let steps = model.undoDepth - depth
        lastChange = steps > 0 ? (reply.id, steps, model.project) : nil
        withAnimation(Fluid.Motion.moderate) {
            messages.append(Message(from: .user, text: text, time: Date()))
            messages.append(reply)
        }
    }

    func canUndo(_ message: Message) -> Bool {
        lastChange?.message == message.id && lastChange?.result == model.project
    }

    func undoLastChange() {
        guard let change = lastChange, change.result == model.project else { return }
        for _ in 0..<change.steps { model.undo() }
        lastChange = nil
        withAnimation(Fluid.Motion.moderate) { messages.append(Message(from: .assistant, text: "Undone.")) }
    }

    // MARK: Understanding

    private func answer(_ text: String) -> String {
        var answers: [String] = []
        var missed: [String] = []
        for phrase in ChatPhrase.clauses(of: text) {
            if let answer = applyFirstMatchingRule(to: phrase) {
                answers.append(answer)
            } else {
                missed.append(phrase.original)
            }
        }
        if answers.isEmpty { return Self.notUnderstood }
        if !missed.isEmpty { answers.append("I didn't understand “\(missed.joined(separator: "”, “"))”.") }
        return answers.joined(separator: " ")
    }

    /// Rules change the project as they match, so each must run once and the first match must end the search.
    private func applyFirstMatchingRule(to phrase: ChatPhrase) -> String? {
        let rules = [helpRule, historyRule, mockupRule, zoomRule, paddingRule, cornerRule, shadowRule, cursorRule, captionRule,
                     aspectRule, backgroundRule, blurRule, soundRule, cutRule, exportRule, playbackRule]
        for rule in rules {
            if let answer = rule(phrase) { return answer }
        }
        return nil
    }

    private var style: RenderStyle { model.project.settings.style }

    private func setStyle(_ change: (inout RenderStyle) -> Void) {
        model.edit { change(&$0.settings.style) }
    }

    private func percent(_ fraction: Double) -> String {
        let value = fraction * 100
        return value == value.rounded() ? "\(Int(value))%" : String(format: "%.1f%%", value)
    }

    private func moveToRequestedTime(_ phrase: ChatPhrase) {
        if let time = phrase.time { model.seek(toOutput: time) }
    }

    private func helpRule(_ phrase: ChatPhrase) -> String? {
        phrase.has("help", "commands") || phrase.contains("what can you") || phrase.contains("what can i") ? Self.help : nil
    }

    private func historyRule(_ phrase: ChatPhrase) -> String? {
        if phrase.has("undo") {
            guard model.canUndo else { return "There's nothing to undo." }
            model.undo()
            return "Undone."
        }
        if phrase.has("redo"), !phrase.has("zoom", "zooms") {
            guard model.canRedo else { return "There's nothing to redo." }
            model.redo()
            return "Done again."
        }
        return nil
    }

    // MARK: Devices

    private func namedDevice(in phrase: ChatPhrase) -> MockupLibrary.Entry? {
        // The longest name first, so that "iPhone 18 Pro Max" isn't read as "iPhone 18 Pro".
        if let exact = library.entries.sorted(by: { $0.name.count > $1.name.count }).first(where: { phrase.contains($0.name.lowercased()) }) {
            return exact
        }
        func entry(_ id: String) -> MockupLibrary.Entry? { library.entries.first { $0.id == id } }
        if phrase.has("macbook", "laptop") || phrase.contains("mac book") {
            if phrase.has("air") { return entry(phrase.has("15") ? "macbook-air-15" : "macbook-air-13") }
            return entry(phrase.has("16") ? "macbook-pro-16" : "macbook-pro-14")
        }
        if phrase.has("iphone", "phone") {
            if phrase.contains("pro max") || phrase.has("max") { return entry("iphone-18-pro-max") }
            if phrase.has("air") { return entry("iphone-air") }
            return entry(phrase.has("pro") ? "iphone-18-pro" : "iphone-17")
        }
        return nil
    }

    private static let motionWords: [(ids: [String], words: [String])] = [
        (["open-from-above"], ["from above", "from the top", "from top"]),
        (["slide-in-open", "slide-in"], ["slide", "slides", "sliding", "from the side", "from side"]),
        (["rise"], ["rise", "rises", "rising", "from below", "from the bottom", "from bottom"]),
        (["hero-reveal"], ["hero", "reveal"]),
        (["whip-turn"], ["whip", "turn open", "turn and open", "from behind"]),
        (["spin-in"], ["spin", "spins", "spinning"]),
        (["slow-orbit"], ["orbit", "orbits", "orbiting"]),
        (["tilt-up"], ["tilt", "tilts", "tilting", "lying flat", "stand up", "stands up", "standing up"]),
        (["idle"], ["idle", "float", "floats", "floating"]),
    ]

    private func mockupRule(_ phrase: ChatPhrase) -> String? {
        let device = namedDevice(in: phrase)
        let saysDevice = phrase.has("mockup", "mockups", "device") || phrase.contains("mock up")
        if phrase.has("remove", "delete", "no", "without", "off", "out") || phrase.contains("get rid"), device != nil || saysDevice {
            guard style.mockup != nil else { return "The video isn't in a device." }
            model.setMockup(nil)
            return "The video is back out of the device."
        }

        let asked = Self.motionWords.first { entry in entry.words.contains { phrase.contains($0) } }
        if let entry = device, let chosen = library.device(id: entry.id) {
            let requested = asked?.ids.compactMap { chosen.motion(id: $0) }.first
            guard let motion = requested ?? style.mockup.flatMap({ chosen.motion(id: $0.motionID) }) ?? chosen.defaultMotion else { return nil }
            model.setMockup(MockupChoice(deviceID: chosen.id, motionID: motion.id))
            var reply = "It's on the \(chosen.name) now, with “\(motion.title)”. It's playing from the start."
            if asked != nil, requested == nil { reply += " The \(chosen.name) can't do the motion you asked for: it has \(motionList(chosen))." }
            return reply
        }
        if let asked {
            guard let current = style.mockup, let chosen = library.device(id: current.deviceID) else {
                return "The video isn't in a device yet. Try “put it in a MacBook”."
            }
            guard let motion = asked.ids.compactMap({ chosen.motion(id: $0) }).first else {
                return "The \(chosen.name) can't do that. It has \(motionList(chosen))."
            }
            model.setMockup(MockupChoice(deviceID: chosen.id, motionID: motion.id))
            return "It now arrives with “\(motion.title)”. It's playing from the start."
        }
        if saysDevice {
            return "Which device? I have \(library.entries.map(\.name).joined(separator: ", "))."
        }
        return nil
    }

    private func motionList(_ device: MockupDevice) -> String {
        device.motions.map(\.title).joined(separator: ", ")
    }

    // MARK: Editing

    private func zoomRule(_ phrase: ChatPhrase) -> String? {
        guard phrase.has("zoom", "zooms") else { return nil }
        if phrase.has("redo", "regenerate", "automatic", "auto", "reset") {
            model.regenerateZooms()
            return "I've made the zooms again from the clicks and typing."
        }
        if phrase.has("off", "remove", "delete", "no", "disable", "without", "stop") {
            guard model.anyZoomEnabled else { return "The zooms are already off." }
            model.setAllZooms(enabled: false)
            return "The zooms are off. They're still there, and the switch on the zoom track brings them back."
        }
        if phrase.has("on", "enable") {
            model.setAllZooms(enabled: true)
            return "The zooms are on."
        }
        moveToRequestedTime(phrase)
        let before = model.project
        model.addZoomAtPlayhead()
        return model.project != before ? "I've added a zoom at \(timecode(model.playhead, tenths: false))." : "There's already a zoom at \(timecode(model.playhead, tenths: false))."
    }

    private func paddingRule(_ phrase: ChatPhrase) -> String? {
        guard phrase.has("padding", "margin", "margins") else { return nil }
        let next: Double
        if phrase.has("no", "none", "zero", "remove") {
            next = 0
        } else if let number = phrase.number {
            next = number / 100
        } else if phrase.has("more", "bigger", "larger", "increase", "add") {
            next = style.padding + 0.03
        } else if phrase.has("less", "smaller", "reduce", "decrease", "tighter") {
            next = style.padding - 0.03
        } else {
            return "The padding is \(percent(style.padding)). Say a size, like “padding 10%”."
        }
        let value = min(max(next, 0), 0.25)
        setStyle { $0.padding = value }
        return "The padding is \(percent(value))."
    }

    private func cornerRule(_ phrase: ChatPhrase) -> String? {
        guard phrase.has("corner", "corners", "radius", "rounded") else { return nil }
        if style.mockup != nil { return "A device has its own corners. Take the video out of the device to change them." }
        let next: Double
        if phrase.has("no", "none", "square", "sharp", "zero") {
            next = 0
        } else if let number = phrase.number {
            next = number / 100
        } else if phrase.has("more", "rounder", "bigger", "larger") {
            next = style.cornerRadius + 0.01
        } else if phrase.has("less", "smaller") {
            next = style.cornerRadius - 0.01
        } else {
            next = 0.02
        }
        let value = min(max(next, 0), 0.05)
        setStyle { $0.cornerRadius = value }
        return "The corner radius is \(percent(value))."
    }

    private func shadowRule(_ phrase: ChatPhrase) -> String? {
        guard phrase.has("shadow", "shadows") else { return nil }
        let next: Double
        if phrase.has("no", "none", "off", "remove", "without") {
            next = 0
        } else if phrase.has("more", "stronger", "bigger", "darker") {
            next = style.shadowOpacity + 0.15
        } else if phrase.has("less", "softer", "lighter", "smaller") {
            next = style.shadowOpacity - 0.15
        } else {
            next = 0.35
        }
        let value = min(max(next, 0), 1)
        setStyle { $0.shadowOpacity = value }
        return value == 0 ? "The shadow is off." : "The shadow is at \(percent(value))."
    }

    private func cursorRule(_ phrase: ChatPhrase) -> String? {
        if phrase.has("click", "clicks"), phrase.has("effect", "effects", "ripple", "ripples") {
            let on = !phrase.has("off", "no", "remove", "hide", "without")
            setStyle { $0.clickEffect = on }
            return on ? "Clicks now show a ripple." : "Clicks no longer show a ripple."
        }
        guard phrase.has("cursor", "mouse", "pointer") else { return nil }
        if phrase.has("hide", "off", "no", "remove", "without") {
            setStyle { $0.showCursor = false }
            return "The cursor is hidden."
        }
        if phrase.has("bigger", "larger", "smaller") {
            let value = min(max(style.cursorScale * (phrase.has("smaller") ? 0.8 : 1.25), 0.6), 3)
            setStyle { $0.cursorScale = value }
            return String(format: "The cursor is at %.1f× now.", value)
        }
        setStyle { $0.showCursor = true }
        return "The cursor is showing."
    }

    private func captionRule(_ phrase: ChatPhrase) -> String? {
        guard phrase.has("caption", "captions", "subtitle", "subtitles") else { return nil }
        if phrase.has("add", "new", "here") {
            moveToRequestedTime(phrase)
            model.addCaptionAtPlayhead()
            return "I've added a caption line at \(timecode(model.playhead, tenths: false)). You can write it in the Captions pane."
        }
        let on = !phrase.has("off", "hide", "no", "remove", "without")
        setStyle { $0.showCaptions = on }
        return on ? "Captions are showing." : "Captions are hidden."
    }

    private func aspectRule(_ phrase: ChatPhrase) -> String? {
        let table: [(AspectChoice, [String])] = [
            (.wide, ["16:9", "widescreen", "wide", "landscape", "youtube"]),
            (.standard, ["4:3"]),
            (.square, ["1:1", "square"]),
            (.portrait, ["4:5", "portrait"]),
            (.vertical, ["9:16", "vertical", "reels", "tiktok", "shorts"]),
        ]
        if phrase.has("aspect", "shape", "ratio"), phrase.has("auto", "automatic", "original") {
            setStyle { $0.aspect = .auto }
            return "The video follows the shape of the screen again."
        }
        for (aspect, words) in table where words.contains(where: { phrase.has($0) }) {
            setStyle { $0.aspect = aspect }
            return "The video is \(aspect.title) now."
        }
        return nil
    }

    private func backgroundRule(_ phrase: ChatPhrase) -> String? {
        if let wallpaper = Wallpapers.all.first(where: { phrase.contains($0.name.lowercased()) || phrase.has($0.id) }) {
            setStyle {
                $0.activeBackground.kind = .wallpaper
                $0.activeBackground.wallpaperID = wallpaper.id
            }
            return "The background is the \(wallpaper.name) wallpaper."
        }
        if phrase.has("wallpaper", "wallpapers") {
            setStyle { $0.activeBackground.kind = .wallpaper }
            return "The background is a wallpaper. I have \(Wallpapers.all.map(\.name).joined(separator: ", "))."
        }
        if phrase.has("gradient") {
            setStyle { $0.activeBackground.kind = .gradient }
            return "The background is a gradient."
        }
        guard phrase.has("background", "backdrop", "solid") else { return nil }
        let colors: [(String, UInt32)] = [("black", 0x000000), ("white", 0xFFFFFF), ("gray", 0x6B7280), ("grey", 0x6B7280), ("red", 0xDC2626),
                                          ("orange", 0xEA580C), ("yellow", 0xFACC15), ("green", 0x16A34A), ("blue", 0x2563EB),
                                          ("purple", 0x7C3AED), ("pink", 0xEC4899)]
        if let color = colors.first(where: { phrase.has($0.0) }) {
            setStyle {
                $0.activeBackground.kind = .solid
                $0.activeBackground.solid = RGB(hex: color.1)
            }
            return "The background is \(color.0)."
        }
        return "Which background? Try a wallpaper name, “gradient”, or a color like “black background”."
    }

    private func blurRule(_ phrase: ChatPhrase) -> String? {
        guard phrase.has("blur", "pixelate", "mask") || phrase.contains("hide something") || phrase.contains("hide this") else { return nil }
        if phrase.has("off", "remove", "delete", "no", "without") {
            guard model.anyMaskEnabled else { return "Nothing is being hidden." }
            model.setAllMasks(enabled: false)
            return "The blurs are off. The switch on the blur track brings them back."
        }
        moveToRequestedTime(phrase)
        model.addMaskAtPlayhead()
        return "I've added a blur at \(timecode(model.playhead, tenths: false)). Drag it in the preview to cover what you want hidden."
    }

    private func soundRule(_ phrase: ChatPhrase) -> String? {
        let muted: Bool
        if phrase.has("unmute") {
            muted = false
        } else if phrase.has("mute") {
            muted = true
        } else if phrase.has("sound", "audio") {
            muted = phrase.has("off", "no", "remove", "without")
        } else {
            return nil
        }
        model.setRecordedSoundMuted(muted)
        return muted ? "The recorded sound is muted." : "The recorded sound is on."
    }

    private func cutRule(_ phrase: ChatPhrase) -> String? {
        if phrase.has("restore"), phrase.has("cut", "cuts", "everything") {
            model.restoreCuts()
            return "Everything that was cut is back."
        }
        if phrase.has("split") || phrase.contains("cut here") || phrase.contains("cut at") {
            moveToRequestedTime(phrase)
            model.splitAtPlayhead()
            return "I've split the clip at \(timecode(model.playhead, tenths: false))."
        }
        if phrase.has("delete", "remove"), phrase.has("clip", "selection", "selected", "this") {
            guard model.selection != .none else { return "Nothing is selected. Click a clip, zoom or blur in the timeline first." }
            model.deleteSelection()
            return "I've deleted what was selected."
        }
        return nil
    }

    private func exportRule(_ phrase: ChatPhrase) -> String? {
        guard phrase.has("export") else { return nil }
        showExport()
        return "The Export pane is open on the right."
    }

    private func playbackRule(_ phrase: ChatPhrase) -> String? {
        if phrase.has("go", "jump", "seek", "skip", "move"), let time = phrase.time ?? phrase.number {
            model.seek(toOutput: time)
            return "I've moved to \(timecode(model.playhead, tenths: false))."
        }
        if phrase.has("rewind", "beginning", "start") {
            model.seek(toOutput: 0)
            return "I've moved to the start."
        }
        if phrase.has("end") {
            model.seek(toOutput: model.outputDuration)
            return "I've moved to the end."
        }
        if phrase.has("pause", "stop") {
            if model.isPlaying { model.togglePlay() }
            return "Paused."
        }
        if phrase.has("play") {
            if !model.isPlaying { model.togglePlay() }
            return "Playing."
        }
        return nil
    }
}

/// One clause of what was typed, tidied for matching: lower case, words and numbers only, single spaces.
struct ChatPhrase {
    let original: String
    private let text: String

    init(_ raw: String) {
        original = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let kept = raw.lowercased()
            .replacingOccurrences(of: "[^a-z0-9:%. ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\.(?!\\d)", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        text = " \(kept) "
    }

    /// Splits a message into its clauses. "Padding 10% and use Glacier" is two things to do, but the names of the
    /// motions have an "and" of their own.
    static func clauses(of message: String) -> [ChatPhrase] {
        var text = message
        for name in ["turn and open", "slide in and open", "rise and open"] {
            text = text.replacingOccurrences(of: name, with: name.replacingOccurrences(of: " and ", with: " "), options: .caseInsensitive)
        }
        return text.replacingOccurrences(of: "(,|;|\\b(and then|then|and|also)\\b)", with: "\n", options: [.regularExpression, .caseInsensitive])
            .split(separator: "\n")
            .map { ChatPhrase(String($0)) }
            .filter { !$0.original.isEmpty }
    }

    /// Whether any of these whole words or phrases is there.
    func has(_ words: String...) -> Bool {
        words.contains { contains($0) }
    }

    func contains(_ words: String) -> Bool {
        text.contains(" \(words) ")
    }

    /// The first plain number, with or without a percent sign. Times like 1:30 don't count.
    var number: Double? {
        for word in text.split(separator: " ") {
            let digits = word.hasSuffix("%") ? word.dropLast() : word
            if let value = Double(digits) { return value }
        }
        return nil
    }

    /// A moment in the video in seconds: "1:30", "90s", "90 seconds", "2 minutes".
    var time: Double? {
        let words = text.split(separator: " ").map(String.init)
        for (index, word) in words.enumerated() {
            let parts = word.split(separator: ":")
            if parts.count == 2, parts[1].count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) {
                return minutes * 60 + seconds
            }
            for (unit, scale) in [("seconds", 1.0), ("second", 1), ("secs", 1), ("sec", 1), ("s", 1), ("minutes", 60), ("minute", 60), ("mins", 60), ("min", 60)] {
                if word.hasSuffix(unit), let value = Double(word.dropLast(unit.count)) { return value * scale }
                if word == unit, index > 0, let value = Double(words[index - 1]) { return value * scale }
            }
        }
        return nil
    }
}
