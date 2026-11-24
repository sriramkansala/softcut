import AppKit
import SoftcutCore
import SwiftUI

/// Where the recording bar is in a recording's life.
public enum RecorderBarPhase: Equatable {
    case idle
    /// Someone is picking a window or drawing an area.
    case choosing
    /// Counting down to the start, with the number to show.
    case countdown(Int)
    case recording(seconds: Int)
    /// Writing the recording to disk.
    case saving
}

/// What the recording bar needs from the app: the choices it shows and what its buttons do.
@MainActor
public protocol RecorderBarControlling: ObservableObject {
    var mode: RecordMode { get set }
    var barPhase: RecorderBarPhase { get }
    var cameras: [InputDevice] { get }
    /// The chosen camera, or nil for none.
    var cameraID: String? { get set }
    var microphones: [InputDevice] { get }
    /// The chosen microphone, or nil for none.
    var microphoneID: String? { get set }
    var systemAudio: Bool { get set }
    var autoZoom: Bool { get set }
    var zoomOnTyping: Bool { get set }

    func refreshDevices()
    func record()
    func stop()
    func cancelCountdown()
    func closeBar()
    func openRecordings()
    func openFolder()
    func quit()
}

/// The floating bar for choosing what to record and starting. While a recording runs it shrinks to a timer and a Stop
/// button. It is a Fluid surface with Fluid's tabs, dropdowns and buttons.
public struct RecorderBarView<Model: RecorderBarControlling>: View {
    @ObservedObject var model: Model

    public init(model: Model) { self.model = model }

    private static var record: Color { Color(fluidHex: 0xEF4444) }

    public var body: some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .environment(\.fluidSurfaceLevel, 3)
            .fluidSurface(3, radius: Fluid.Radius.container + 4, shadow: 5)
            .environment(\.colorScheme, .dark)
            .fixedSize()
            // Room around the bar for its shadow.
            .padding(20)
            .animation(Fluid.Motion.slow, value: model.barPhase)
    }

    @ViewBuilder private var content: some View {
        switch model.barPhase {
        case .idle, .choosing: idle.transition(.opacity.animation(Fluid.Motion.moderate))
        case .countdown(let number): countdown(number).transition(.opacity.animation(Fluid.Motion.moderate))
        case .recording(let seconds): recording(seconds).transition(.opacity.animation(Fluid.Motion.moderate))
        case .saving: saving.transition(.opacity.animation(Fluid.Motion.moderate))
        }
    }

    // MARK: Choosing

    private var idle: some View {
        HStack(spacing: 4) {
            FluidIconButton(systemName: "xmark", help: "Close the bar (Esc). Softcut stays in the menu bar.") { model.closeBar() }
                .keyboardShortcut(.cancelAction)

            separator
            FluidTabs(selection: $model.mode, items: RecordMode.allCases.map { FluidTabItem($0, Self.title(for: $0), icon: Self.icon(for: $0)) })
                .fluidTooltip(Self.help(for: model.mode))
            separator

            FluidDropdown(rows: {
                [.item("No camera", icon: "video.slash", checked: model.cameraID == nil, id: AnyHashable("none")) { model.cameraID = nil }]
                    + model.cameras.map { camera in
                        .item(camera.name, icon: "video", checked: model.cameraID == camera.id, id: AnyHashable(camera.id)) { model.cameraID = camera.id }
                    }
            }, width: 260, placement: .below) { open in
                DeviceChip(on: model.cameraID != nil, onIcon: "video.fill", offIcon: "video.slash",
                           text: name(of: model.cameraID, in: model.cameras) ?? "No camera", isOpen: open)
            }

            FluidDropdown(rows: {
                [.item("No microphone", icon: "mic.slash", checked: model.microphoneID == nil, id: AnyHashable("none")) { model.microphoneID = nil }]
                    + model.microphones.map { mic in
                        .item(mic.name, icon: "mic", checked: model.microphoneID == mic.id, id: AnyHashable(mic.id)) { model.microphoneID = mic.id }
                    }
            }, width: 260, placement: .below) { open in
                DeviceChip(on: model.microphoneID != nil, onIcon: "mic.fill", offIcon: "mic.slash",
                           text: name(of: model.microphoneID, in: model.microphones) ?? "No mic", isOpen: open)
            }

            Button { model.systemAudio.toggle() } label: {
                DeviceChip(on: model.systemAudio, onIcon: "speaker.wave.2.fill", offIcon: "speaker.slash",
                           text: model.systemAudio ? "System audio" : "System off", isOpen: false, showsChevron: false)
            }
            .buttonStyle(.plain)
            .fluidTooltip("Record the sounds your Mac plays")

            separator

            FluidIconButton(systemName: "folder", help: "Your recordings") { model.openRecordings() }
            settingsMenu

            Button { model.record() } label: {
                HStack(spacing: 6) {
                    Circle().fill(Self.record).frame(width: 9, height: 9)
                    Text(recordTitle)
                }
            }
            .buttonStyle(FluidButtonStyle(variant: .primary, size: .regular, leadingIcon: true))
            .keyboardShortcut(.defaultAction)
            .fluidTooltip("Start recording (Control + Option + R)")
            .padding(.leading, 4)
        }
        .onAppear { model.refreshDevices() }
    }

    private var recordTitle: String {
        switch model.mode {
        case .display: return "Record"
        case .window: return "Pick a window"
        case .area: return "Select an area"
        }
    }

    static func icon(for mode: RecordMode) -> String {
        switch mode {
        case .display: return "display"
        case .window: return "macwindow"
        case .area: return "rectangle.dashed"
        }
    }

    static func title(for mode: RecordMode) -> String {
        switch mode {
        case .display: return "Display"
        case .window: return "Window"
        case .area: return "Area"
        }
    }

    static func help(for mode: RecordMode) -> String {
        switch mode {
        case .display: return "Record the whole screen"
        case .window: return "Record one window, with other windows out of the way"
        case .area: return "Draw a rectangle to record. The whole screen is kept, so you can widen it later in the editor."
        }
    }

    private func name(of id: String?, in devices: [InputDevice]) -> String? {
        guard let id else { return nil }
        return devices.first { $0.id == id }?.name ?? "Unavailable"
    }

    private var settingsMenu: some View {
        FluidDropdown(rows: {
            [.label("Automatic zoom"),
             .item("Zoom on clicks", checked: model.autoZoom) { model.autoZoom.toggle() },
             .item("Zoom on typing", checked: model.zoomOnTyping) { model.zoomOnTyping.toggle() },
             .separator(),
             .item("Recordings…", icon: "film.stack") { model.openRecordings() },
             .item("Open recordings folder", icon: "folder") { model.openFolder() },
             .separator(),
             .label("Start or stop anywhere: ⌃⌥R"),
             .item("Quit Softcut", icon: "power") { model.quit() }]
        }, width: 240, placement: .belowTrailing) { open in
            DeviceChip(on: true, onIcon: "gearshape", offIcon: "gearshape", text: nil, isOpen: open, tinted: false)
        }
        .fluidTooltip("Settings")
    }

    private var separator: some View {
        Rectangle().fill(Fluid.border).frame(width: 1, height: 20).padding(.horizontal, 4)
    }

    // MARK: Counting down, recording, saving

    private func countdown(_ number: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Fluid.foreground)
                .frame(width: 44)
                .contentTransition(.numericText(countsDown: true))
                .animation(Fluid.Motion.moderate, value: number)
            VStack(alignment: .leading, spacing: 2) {
                Text("Recording starts…").font(Fluid.font(.subtitle, .semibold)).foregroundStyle(Fluid.foreground)
                Text("Get your screen ready").font(Fluid.font(.caption)).foregroundStyle(Fluid.mutedForeground)
            }
            FluidButton("Cancel", variant: .secondary) { model.cancelCountdown() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 6)
    }

    private func recording(_ seconds: Int) -> some View {
        HStack(spacing: 12) {
            PulsingDot(color: Self.record)
                .padding(.leading, 8)
            Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                .font(.system(size: 16, weight: .medium).monospacedDigit())
                .foregroundStyle(Fluid.foreground)
                .frame(minWidth: 48, alignment: .leading)
            Button { model.stop() } label: {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(Self.record).frame(width: 9, height: 9)
                    Text("Stop")
                }
            }
            .buttonStyle(FluidButtonStyle(variant: .primary, size: .regular, leadingIcon: true))
            .fluidTooltip("Stop recording (Control + Option + R)")
        }
    }

    private var saving: some View {
        FluidThinkingIndicator(words: ["Saving", "Putting it together"])
    }
}

/// A device choice on the bar: its icon (lit when on, struck through when off), its name, and a chevron for the list.
private struct DeviceChip: View {
    let on: Bool
    let onIcon: String
    let offIcon: String
    let text: String?
    let isOpen: Bool
    var showsChevron = true
    var tinted = true
    @State private var hovered = false

    var body: some View {
        let lit = hovered || isOpen
        HStack(spacing: 6) {
            Image(systemName: on ? onIcon : offIcon)
                .font(.system(size: 12, weight: lit ? .semibold : .regular))
                .foregroundStyle(on && tinted ? Fluid.focusRing : (lit ? Fluid.foreground : Fluid.mutedForeground))
                .frame(width: 16)
            if let text {
                Text(text)
                    .font(Fluid.font(.body))
                    .lineLimit(1)
                    .frame(maxWidth: 96, alignment: .leading)
                    .foregroundStyle(on || lit ? Fluid.foreground : Fluid.mutedForeground)
                    .fixedSize()
            }
            if showsChevron {
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                    .foregroundStyle(lit ? Fluid.foreground : Fluid.mutedForeground)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 36)
        .background(isOpen ? Fluid.active : (hovered ? Fluid.hover : .clear), in: RoundedRectangle(cornerRadius: Fluid.Radius.item, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.08), value: hovered)
    }
}

private struct PulsingDot: View {
    let color: Color
    @State private var bright = true

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .opacity(bright ? 1 : 0.3)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: bright)
            .onAppear { bright = false }
    }
}

// MARK: Previews and pictures

/// A recording bar with nothing behind it, for drawing it to a picture.
@MainActor
public final class PreviewRecorderBar: RecorderBarControlling {
    @Published public var mode: RecordMode
    @Published public var barPhase: RecorderBarPhase
    @Published public var cameraID: String?
    @Published public var microphoneID: String?
    @Published public var systemAudio: Bool
    @Published public var autoZoom = true
    @Published public var zoomOnTyping = false
    public var cameras = [InputDevice(id: "cam", name: "FaceTime HD Camera")]
    public var microphones = [InputDevice(id: "mic", name: "MacBook Pro Microphone")]
    public private(set) var calls: [String] = []

    public init(mode: RecordMode = .display, phase: RecorderBarPhase = .idle, camera: Bool = false, microphone: Bool = false, systemAudio: Bool = false) {
        self.mode = mode
        self.barPhase = phase
        self.cameraID = camera ? "cam" : nil
        self.microphoneID = microphone ? "mic" : nil
        self.systemAudio = systemAudio
    }

    public func refreshDevices() { calls.append("refresh") }
    public func record() { calls.append("record") }
    public func stop() { calls.append("stop") }
    public func cancelCountdown() { calls.append("cancel") }
    public func closeBar() { calls.append("close") }
    public func openRecordings() { calls.append("recordings") }
    public func openFolder() { calls.append("folder") }
    public func quit() { calls.append("quit") }
}

public enum RecorderBarSnapshot {
    /// The bar drawn over a stand-in desktop.
    @MainActor
    public static func render(_ model: PreviewRecorderBar) async -> NSBitmapImageRep? {
        let size = CGSize(width: 1240, height: 150)
        let picture = ZStack {
            LinearGradient(colors: [Color(red: 0.42, green: 0.55, blue: 1.0), Color(red: 0.74, green: 0.68, blue: 0.98)], startPoint: .top, endPoint: .bottom)
            RecorderBarView(model: model)
        }
        .frame(width: size.width, height: size.height)

        let host = NSHostingView(rootView: picture)
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(300))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }
}
