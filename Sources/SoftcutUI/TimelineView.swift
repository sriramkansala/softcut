import AppKit
import SoftcutCore
import Combine
import SwiftUI

/// The editing tools above the tracks: cutting and pasting, adding zooms, blurs and captions on the left; delete,
/// undo, redo and the timeline's scale on the right.
private struct TimelineBar: View {
    @ObservedObject var model: EditorModel
    let fit: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            FluidIconButton(systemName: "scissors", help: "Split the clip at the playhead (S)") { model.splitAtPlayhead() }
                .keyboardShortcut("s", modifiers: [])
            FluidIconButton(systemName: "scissors.badge.ellipsis", help: "Cut the selected clip (⌘X). Paste it anywhere, or at the end.") { model.cutSelection() }
                .keyboardShortcut("x", modifiers: .command)
                .disabled(!canCut)
            FluidIconButton(systemName: "doc.on.doc", help: "Copy the selected clip (⌘C)") { model.copySelection() }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(!isClipSelected)
            FluidDropdown(rows: {
                [.item("Paste after this clip", icon: "doc.on.clipboard") { model.paste() },
                 .item("Paste at the end", icon: "arrow.down.to.line") { model.pasteAtEnd() }]
            }, width: 220) { open in
                ToolbarMenuLabel(icon: "doc.on.clipboard", isOpen: open)
            }
            .disabled(!model.canPaste)
            .fluidTooltip("Paste the clip you cut or copied (⌘V), or at the end (⇧⌘V)")
            .background {
                // The paste shortcuts work without opening the menu.
                Group {
                    Button("") { model.paste() }.keyboardShortcut("v", modifiers: .command)
                    Button("") { model.pasteAtEnd() }.keyboardShortcut("v", modifiers: [.command, .shift])
                }
                .disabled(!model.canPaste)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }

            separator

            FluidIconButton(systemName: "plus.viewfinder", help: "Add a zoom at the playhead (Z)") { model.addZoomAtPlayhead() }
                .keyboardShortcut("z", modifiers: [])
            FluidIconButton(systemName: "eye.slash", help: "Hide a part of the screen for a while (B)") { model.addMaskAtPlayhead() }
                .keyboardShortcut("b", modifiers: [])
            FluidIconButton(systemName: "textformat", help: "Add a caption line at the playhead") { model.addCaptionAtPlayhead() }

            Spacer()

            FluidIconButton(systemName: "trash", help: "Delete the selected clip, zoom or blur (Delete)") { model.deleteSelection() }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(model.selection == .none)
            separator
            FluidIconButton(systemName: "arrow.uturn.backward", help: "Undo (⌘Z)") { model.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!model.canUndo)
            FluidIconButton(systemName: "arrow.uturn.forward", help: "Redo (⇧⌘Z)") { model.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!model.canRedo)
            separator
            FluidIconButton(systemName: "minus.magnifyingglass", help: "Show more of the video") {
                withAnimation(Fluid.Motion.moderate) { model.pixelsPerSecond = max(8, model.pixelsPerSecond / 1.5) }
            }
            FluidIconButton(systemName: "plus.magnifyingglass", help: "Show the video in more detail") {
                withAnimation(Fluid.Motion.moderate) { model.pixelsPerSecond = min(400, model.pixelsPerSecond * 1.5) }
            }
            FluidIconButton(systemName: "arrow.down.left.and.arrow.up.right", help: "Fit the whole video") { withAnimation(Fluid.Motion.moderate) { fit() } }
        }
        .padding(.horizontal, 10)
    }

    private var separator: some View {
        Rectangle().fill(Fluid.border).frame(width: 1, height: 16).padding(.horizontal, 6)
    }

    private var isClipSelected: Bool {
        if case .slice = model.selection { return true }
        return false
    }

    private var canCut: Bool { isClipSelected && model.project.slices.count > 1 }
}

/// A ghost trigger for a toolbar menu: an icon, an optional title and a small chevron, held lit while open.
private struct ToolbarMenuLabel: View {
    let icon: String
    var title: String?
    let isOpen: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 13, weight: hovered || isOpen ? .semibold : .regular))
            if let title { Text(title).font(Fluid.font(.body)) }
            Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
        }
        .foregroundStyle(hovered || isOpen ? Fluid.foreground : Fluid.mutedForeground)
        .padding(.horizontal, 7)
        .frame(height: 28)
        .background(isOpen ? Fluid.active : (hovered ? Fluid.hover : .clear), in: RoundedRectangle(cornerRadius: Fluid.Radius.item, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovered = $0 && isEnabled }
        .opacity(isEnabled ? 1 : 0.5)
        .animation(.easeOut(duration: 0.08), value: hovered)
    }
}

/// The timeline panel: the time and tools along the top; then a header for each track beside the tracks themselves,
/// which scroll sideways.
struct TimelineView: View {
    @ObservedObject var model: EditorModel
    let projectMenu: ProjectMenu?
    @State private var width: CGFloat = 0

    static let headerWidth: CGFloat = 196
    static let toolsHeight: CGFloat = 46
    static let height: CGFloat = toolsHeight + 1 + TimelineTracks.contentHeight

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                TimeReadout(clock: model.clock, duration: model.outputDuration)
                    .accessibilityLabel("Time")
                    .padding(.leading, 16)
                    .frame(width: Self.headerWidth)
                TimelineBar(model: model, fit: fit)
            }
            .frame(height: Self.toolsHeight)
            Rectangle().fill(Fluid.border).frame(height: 1)
            HStack(spacing: 0) {
                TrackHeaders(model: model).frame(width: Self.headerWidth)
                GeometryReader { geometry in
                    ScrollView(.horizontal, showsIndicators: false) {
                        TimelineTracks(model: model, minWidth: geometry.size.width)
                    }
                    .onAppear { width = geometry.size.width; fit() }
                    .onChange(of: geometry.size.width) { _, new in width = new }
                    // Adding or removing clips changes the length; keep the whole video in view.
                    .onChange(of: model.outputDuration) { old, new in
                        if abs(old - new) > 0.5 { fit() }
                    }
                }
            }
        }
        .overlay(alignment: .topLeading) {
            Rectangle().fill(Fluid.border).frame(width: 1).offset(x: Self.headerWidth)
        }
        .background(Theme.panel, in: shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
        .clipShape(shape)
    }

    private func fit() {
        guard width > 40, model.outputDuration > 0 else { return }
        model.pixelsPerSecond = max(8, Double(width - TimelineTracks.leading - 24) / model.outputDuration)
    }
}

/// The time at the playhead and the length of the video. This and `PlayheadMarker` are the only things that move during
/// playback, and they are drawn directly so that playing a video asks nothing of SwiftUI: a single changed `Text` has it
/// lay out and draw the whole window again, 30 times a second.
private struct TimeReadout: NSViewRepresentable {
    let clock: PlayheadClock
    let duration: Double

    func makeNSView(context: Context) -> TimeReadoutView { TimeReadoutView(clock: clock) }
    func updateNSView(_ view: TimeReadoutView, context: Context) { view.duration = duration }
}

final class TimeReadoutView: NSView {
    var duration = 0.0 {
        didSet { if duration != oldValue { needsDisplay = true } }
    }
    private var time = ""
    private var watching: AnyCancellable?

    init(clock: PlayheadClock) {
        super.init(frame: .zero)
        watching = clock.$time.sink { [weak self] seconds in
            guard let self else { return }
            let text = timecode(seconds)
            if text != self.time {
                self.time = text
                self.needsDisplay = true
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        let text = NSMutableAttributedString(string: time, attributes: [.font: font, .foregroundColor: NSColor(Fluid.foreground)])
        text.append(NSAttributedString(string: " / \(timecode(duration))", attributes: [.font: font, .foregroundColor: NSColor(Fluid.mutedForeground)]))
        text.draw(at: NSPoint(x: 0, y: ((bounds.height - text.size().height) / 2).rounded()))
    }
}

/// The line across the tracks at the playhead, with its handle. The handle sits on the ruler, and dragging there moves the
/// playhead, so this only has to be drawn.
private struct PlayheadMarker: NSViewRepresentable {
    let clock: PlayheadClock
    let leading: CGFloat
    let pixelsPerSecond: Double

    func makeNSView(context: Context) -> PlayheadMarkerView { PlayheadMarkerView(clock: clock) }

    func updateNSView(_ view: PlayheadMarkerView, context: Context) {
        view.place(leading: leading, pixelsPerSecond: pixelsPerSecond)
    }
}

final class PlayheadMarkerView: NSView {
    private let marker = CALayer()
    private var leading: CGFloat = 0
    private var pixelsPerSecond = 0.0
    private var time = 0.0
    private var watching: AnyCancellable?

    override var isFlipped: Bool { true }

    init(clock: PlayheadClock) {
        super.init(frame: .zero)
        wantsLayer = true
        let color = NSColor(Theme.playhead).cgColor
        let height = TimelineTracks.contentHeight

        marker.anchorPoint = CGPoint(x: 0.5, y: 0)
        marker.bounds = CGRect(x: 0, y: 0, width: 12, height: height)

        let line = CALayer()
        line.backgroundColor = color
        line.frame = CGRect(x: 5.25, y: 0, width: 1.5, height: height)
        marker.addSublayer(line)

        let handle = CAShapeLayer()
        handle.path = Self.handlePath(in: CGRect(x: 0, y: 2, width: 12, height: 18))
        handle.fillColor = color
        handle.shadowColor = color
        handle.shadowOpacity = 0.5
        handle.shadowRadius = 4
        handle.shadowOffset = .zero
        marker.addSublayer(handle)
        layer?.addSublayer(marker)

        watching = clock.$time.sink { [weak self] seconds in
            self?.time = seconds
            self?.move()
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func place(leading: CGFloat, pixelsPerSecond: Double) {
        self.leading = leading
        self.pixelsPerSecond = pixelsPerSecond
        move()
    }

    private func move() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        marker.position = CGPoint(x: leading + CGFloat(time * pixelsPerSecond), y: 0)
        CATransaction.commit()
    }

    /// A rectangle with small top corners and larger bottom ones.
    private static func handlePath(in rect: CGRect) -> CGPath {
        let (top, bottom): (CGFloat, CGFloat) = (4, 6)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX + top, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: top)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: bottom)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: bottom)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: top)
        path.closeSubpath()
        return path
    }
}

/// A header card for each track, level with it: its name and how many things it holds, and switches for the whole
/// track.
private struct TrackHeaders: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        let clips = model.project.slices.count
        let zooms = model.allZooms.count
        let masks = model.allMasks.count
        ZStack(alignment: .topLeading) {
            header(code: "V1", name: "Video", count: clips == 1 ? "1 clip" : "\(clips) clips",
                   top: TimelineTracks.clipLaneTop, height: TimelineTracks.clipLaneHeight, stacked: true) {
                LaneToggle(on: !model.recordedSoundMuted, onIcon: "speaker.wave.2", offIcon: "speaker.slash",
                           help: model.recordedSoundMuted ? "Turn the recorded sound back on" : "Mute the recorded sound") {
                    model.setRecordedSoundMuted(!model.recordedSoundMuted)
                }
                LaneToggle(on: model.project.settings.style.showCursor, onIcon: "cursorarrow", offIcon: "cursorarrow.slash",
                           help: model.project.settings.style.showCursor ? "Hide the cursor" : "Show the cursor") {
                    model.edit { $0.settings.style.showCursor.toggle() }
                }
            }
            header(code: "Z1", name: "Zooms", count: "\(zooms)", top: TimelineTracks.zoomLaneTop, height: TimelineTracks.zoomLaneHeight) {
                LaneToggle(on: model.anyZoomEnabled, onIcon: "eye", offIcon: "eye.slash",
                           help: model.anyZoomEnabled ? "Switch every zoom off" : "Switch every zoom on") {
                    model.setAllZooms(enabled: !model.anyZoomEnabled)
                }
                .disabled(zooms == 0)
            }
            header(code: "B1", name: "Blur", count: "\(masks)", top: TimelineTracks.maskLaneTop, height: TimelineTracks.maskLaneHeight) {
                LaneToggle(on: model.anyMaskEnabled, onIcon: "eye", offIcon: "eye.slash",
                           help: model.anyMaskEnabled ? "Switch every hidden area off" : "Switch every hidden area on") {
                    model.setAllMasks(enabled: !model.anyMaskEnabled)
                }
                .disabled(masks == 0)
            }
        }
        .frame(height: TimelineTracks.contentHeight, alignment: .topLeading)
    }

    private func header<Toggles: View>(code: String, name: String, count: String, top: CGFloat, height: CGFloat, stacked: Bool = false,
                                       @ViewBuilder toggles: () -> Toggles) -> some View {
        let label = HStack(spacing: 10) {
            Text(code).font(.system(size: 10.5, weight: .medium).monospacedDigit()).foregroundStyle(Fluid.mutedForeground)
            Text(name).font(Fluid.font(.body, .semibold)).foregroundStyle(Fluid.foreground)
            Spacer(minLength: 4)
            Text(count).font(Fluid.font(.caption, monospacedDigits: true)).foregroundStyle(Fluid.mutedForeground)
        }
        return Group {
            if stacked {
                VStack(alignment: .leading, spacing: 0) {
                    label
                    Spacer(minLength: 0)
                    // The switches' hit areas reach past their icons, so it is the icons that line up with the padding.
                    HStack(spacing: 2) { Spacer(); toggles() }
                        .padding(.trailing, -7)
                        .padding(.bottom, -6)
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 10)
            } else {
                HStack(spacing: 4) { label; toggles() }.padding(.leading, 10).padding(.trailing, 6)
            }
        }
        .frame(width: TimelineView.headerWidth - 16, height: height)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .offset(x: 8, y: top)
    }
}

/// A small switch for a whole track, drawn as its icon: lit when on, struck through when off.
private struct LaneToggle: View {
    let on: Bool
    let onIcon: String
    let offIcon: String
    let help: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: on ? onIcon : offIcon)
                .font(.system(size: 11, weight: hovered ? .semibold : .regular))
                .foregroundStyle(hovered ? Fluid.foreground : (on ? Fluid.mutedForeground : Fluid.mutedForeground.opacity(0.6)))
                .frame(width: 24, height: 24)
                .background(hovered ? Fluid.hover : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 && isEnabled }
        .opacity(isEnabled ? 1 : 0.4)
        .fluidTooltip(help)
        .accessibilityLabel(help)
    }
}

/// A zoom or blur as it appears on the timeline: one block for each place its stretch of a recording is in the video.
private struct RangePiece: Identifiable {
    let id: String
    let itemID: UUID
    let piece: TimeMap.Piece
    let startsHere: Bool
    let endsHere: Bool
}

struct TimelineTracks: View {
    @ObservedObject var model: EditorModel
    let minWidth: CGFloat

    static let leading: CGFloat = 14
    static let rulerHeight: CGFloat = 28
    static let clipHeight: CGFloat = 66
    static let zoomHeight: CGFloat = 30
    static let maskHeight: CGFloat = 26
    /// Room between a track's band and the blocks in it.
    static let inset: CGFloat = 3
    static let gap: CGFloat = 6

    static let clipLaneTop = rulerHeight + 4
    static let clipLaneHeight = clipHeight + inset * 2
    static let zoomLaneTop = clipLaneTop + clipLaneHeight + gap
    static let zoomLaneHeight = zoomHeight + inset * 2
    static let maskLaneTop = zoomLaneTop + zoomLaneHeight + gap
    static let maskLaneHeight = maskHeight + inset * 2
    static let contentHeight = maskLaneTop + maskLaneHeight + 10

    private var pps: Double { model.pixelsPerSecond }
    private var clipTop: CGFloat { Self.clipLaneTop + Self.inset }
    private var zoomTop: CGFloat { Self.zoomLaneTop + Self.inset }
    private var maskTop: CGFloat { Self.maskLaneTop + Self.inset }

    private func x(_ time: Double) -> CGFloat { Self.leading + CGFloat(time * pps) }
    private func time(_ x: CGFloat) -> Double { Double(x - Self.leading) / pps }

    var body: some View {
        let contentWidth = max(minWidth, x(model.outputDuration) + 24)
        let timeMap = model.project.timeMap
        ZStack(alignment: .topLeading) {
            // Clicking empty space moves the playhead there and clears the selection.
            Rectangle().fill(Color.clear).contentShape(Rectangle())
                .gesture(SpatialTapGesture(coordinateSpace: .named("timeline")).onEnded { value in
                    model.selection = .none
                    model.seek(toOutput: time(value.location.x))
                })

            ruler
            lane(top: Self.clipLaneTop, height: Self.clipLaneHeight, width: contentWidth)
            lane(top: Self.zoomLaneTop, height: Self.zoomLaneHeight, width: contentWidth)
            lane(top: Self.maskLaneTop, height: Self.maskLaneHeight, width: contentWidth)

            ForEach(Array(timeMap.segments.enumerated()), id: \.element.id) { index, clip in
                clipBlock(clip, index: index, start: timeMap.outputStarts[index])
            }
            clickMarks(timeMap)
            ForEach(zoomPieces(timeMap)) { piece in zoomBlock(piece, timeMap: timeMap) }
            ForEach(maskPieces(timeMap)) { piece in maskBlock(piece, timeMap: timeMap) }

            playhead
        }
        .frame(width: contentWidth, height: Self.contentHeight, alignment: .topLeading)
        .coordinateSpace(name: "timeline")
    }

    // MARK: Ruler

    private var ruler: some View {
        Canvas { context, size in
            let steps: [Double] = [0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600]
            let major = steps.first { $0 * pps >= 70 } ?? 600
            let minor = major / (major >= 10 ? 5 : (major >= 2 ? 4 : 5))
            let ticksPerMajor = Int((major / minor).rounded())
            let tickCount = Int((model.outputDuration + major) / minor) + 1
            for index in 0..<tickCount {
                let t = Double(index) * minor
                let px = x(t)
                let isMajor = index % ticksPerMajor == 0
                var tick = Path()
                tick.move(to: CGPoint(x: px, y: Self.rulerHeight))
                tick.addLine(to: CGPoint(x: px, y: Self.rulerHeight - (isMajor ? 9 : 4)))
                context.stroke(tick, with: .color(.white.opacity(isMajor ? 0.45 : 0.22)), lineWidth: 1)
                if isMajor {
                    context.draw(Text(timecode(t, tenths: major < 1)).font(.system(size: 9.5).monospacedDigit()).foregroundStyle(Fluid.mutedForeground),
                                 at: CGPoint(x: px + 4, y: Self.rulerHeight - 12), anchor: .leading)
                }
            }
        }
        .frame(height: Self.rulerHeight)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("timeline")).onChanged { value in
            model.seek(toOutput: time(value.location.x))
        })
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// A track's band, running the whole width of the timeline.
    private func lane(top: CGFloat, height: CGFloat, width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(0.035))
            .frame(width: max(0, width - Self.leading + Self.inset - 8), height: height)
            .offset(x: Self.leading - Self.inset, y: top)
            .allowsHitTesting(false)
    }

    /// Where the mouse was clicked, so the moments that matter are easy to find.
    private func clickMarks(_ timeMap: TimeMap) -> some View {
        let marks: [(id: String, x: CGFloat)] = timeMap.segments.enumerated().flatMap { index, clip -> [(id: String, x: CGFloat)] in
            guard let recording = model.sources.bundle(clip.sourceID) else { return [] }
            let start = timeMap.outputStarts[index]
            return recording.input.clicks.enumerated().compactMap { offset, click in
                guard click.down, click.t >= clip.sourceStart, click.t <= clip.sourceEnd else { return nil }
                return ("\(index)-\(offset)", x(start + (click.t - clip.sourceStart) / clip.speed))
            }
        }
        return ForEach(marks, id: \.id) { mark in
            Circle().fill(Color.white.opacity(0.85)).frame(width: 4, height: 4)
                .shadow(color: .black.opacity(0.6), radius: 1)
                .offset(x: mark.x - 2, y: clipTop + Self.clipHeight - Self.labelHeight - 8)
        }
        .allowsHitTesting(false)
    }

    // MARK: Clips

    private static let palette: [Color] = [Theme.clip, Color(red: 0.20, green: 0.62, blue: 0.60), Color(red: 0.62, green: 0.38, blue: 0.82),
                                           Color(red: 0.80, green: 0.42, blue: 0.55), Color(red: 0.52, green: 0.66, blue: 0.28)]

    private func color(for source: UUID?) -> Color {
        let index = model.sourceOrder.firstIndex { $0 == source } ?? 0
        return Self.palette[index % Self.palette.count]
    }

    static let labelHeight: CGFloat = 18

    /// A clip: a filmstrip of its recording, with its name, speed and length on a strip along the bottom. The chosen
    /// clip is outlined and its strip turns pale.
    private func clipBlock(_ clip: TimeSegment, index: Int, start: Double) -> some View {
        let selected = model.selection == .slice(clip.id)
        let width = max(6, CGFloat(clip.outputDuration * pps))
        let tint = color(for: clip.sourceID)
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let manifest = (model.sources.bundle(clip.sourceID) ?? model.bundle).manifest
        let aspect = manifest.displayWidth / max(1, manifest.displayHeight)
        let pale = Color(fluidHex: 0xDCE6F7)
        return VStack(spacing: 0) {
            ClipFilmstrip(strip: model.filmstrip(for: clip.sourceID), sourceStart: clip.sourceStart, speed: clip.speed,
                          pixelsPerSecond: pps, aspect: aspect, tint: tint)
                .overlay(Color.black.opacity(selected ? 0 : 0.22))
            HStack(spacing: 6) {
                if width > 90 {
                    Text(model.name(of: clip.sourceID)).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
                if clip.hideCursor { Image(systemName: "cursorarrow.slash").font(.system(size: 9, weight: .semibold)) }
                if clip.speed != 1 {
                    Text(clip.speed == clip.speed.rounded() ? "\(Int(clip.speed))×" : String(format: "%.1f×", clip.speed))
                        .font(.system(size: 9.5, weight: .bold))
                }
                if width > 50 { Text(timecode(clip.outputDuration)).monospacedDigit() }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(selected ? Color(fluidHex: 0x1A2233) : Color.white.opacity(0.85))
            .padding(.horizontal, 8)
            .frame(height: Self.labelHeight)
            .background(selected ? pale : tint.mix(with: .black, by: 0.5).opacity(0.92))
            .allowsHitTesting(false)
        }
        .frame(width: width, height: Self.clipHeight)
        .background(tint.opacity(0.35))
        .clipShape(shape)
        .overlay(shape.strokeBorder(selected ? pale : Color.white.opacity(0.12), lineWidth: selected ? 2 : 1))
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture(coordinateSpace: .named("timeline")).onEnded { value in
            model.selection = .slice(clip.id)
            model.seek(toOutput: time(value.location.x))
        })
        .overlay(alignment: .leading) {
            EdgeHandle { model.trimSlice(clip.id, start: model.sourceTime(inClip: index, atOutput: time($0))) }
        }
        .overlay(alignment: .trailing) {
            EdgeHandle { model.trimSlice(clip.id, end: model.sourceTime(inClip: index, atOutput: time($0))) }
        }
        .offset(x: x(start), y: clipTop)
    }

    // MARK: Zooms and blurs

    private func pieces(of items: [(id: UUID, source: UUID?, start: Double, end: Double)], in timeMap: TimeMap) -> [RangePiece] {
        items.flatMap { item in
            timeMap.pieces(source: item.source, sourceStart: item.start, sourceEnd: item.end).map { piece in
                RangePiece(id: "\(item.id)-\(piece.segmentIndex)", itemID: item.id, piece: piece,
                           startsHere: abs(piece.sourceStart - item.start) < 0.001, endsHere: abs(piece.sourceEnd - item.end) < 0.001)
            }
        }
    }

    private func zoomPieces(_ timeMap: TimeMap) -> [RangePiece] {
        pieces(of: model.allZooms.map { ($0.zoom.id, $0.source, $0.zoom.start, $0.zoom.end) }, in: timeMap)
    }

    private func maskPieces(_ timeMap: TimeMap) -> [RangePiece] {
        pieces(of: model.allMasks.map { ($0.mask.id, $0.source, $0.mask.start, $0.mask.end) }, in: timeMap)
    }

    private func zoomBlock(_ item: RangePiece, timeMap: TimeMap) -> some View {
        let zoom = model.project.zoom(item.itemID)
        let index = item.piece.segmentIndex
        let speed = timeMap.segments[index].speed
        return RangeBlock(
            color: Theme.zoom, icon: zoom?.presentation == .loupe ? "circle.dashed" : (zoom?.follow == .fixed ? "scope" : "plus.magnifyingglass"),
            label: String(format: "%.1f×", zoom?.scale ?? 2), selected: model.selection == .zoom(item.itemID), dimmed: zoom?.isDisabled == true,
            x: x(item.piece.outputStart), top: zoomTop, width: max(8, CGFloat((item.piece.outputEnd - item.piece.outputStart) * pps)),
            height: Self.zoomHeight, pixelsPerSecond: pps, showsStartHandle: item.startsHere, showsEndHandle: item.endsHere,
            start: zoom?.start ?? 0, speed: speed,
            onSelect: { model.selection = .zoom(item.itemID) },
            onMove: { start in model.moveZoom(item.itemID, toStart: start) },
            onResizeStart: { model.resizeZoom(item.itemID, start: model.sourceTime(inClip: index, atOutput: time($0))) },
            onResizeEnd: { model.resizeZoom(item.itemID, end: model.sourceTime(inClip: index, atOutput: time($0))) })
    }

    private func maskBlock(_ item: RangePiece, timeMap: TimeMap) -> some View {
        let mask = model.project.mask(item.itemID)
        let index = item.piece.segmentIndex
        let speed = timeMap.segments[index].speed
        return RangeBlock(
            color: Color(red: 0.25, green: 0.70, blue: 0.72), icon: "eye.slash", label: mask?.kind.title ?? "Blur",
            selected: model.selection == .mask(item.itemID), dimmed: mask?.isDisabled == true,
            x: x(item.piece.outputStart), top: maskTop, width: max(8, CGFloat((item.piece.outputEnd - item.piece.outputStart) * pps)),
            height: Self.maskHeight, pixelsPerSecond: pps, showsStartHandle: item.startsHere, showsEndHandle: item.endsHere,
            start: mask?.start ?? 0, speed: speed,
            onSelect: { model.selection = .mask(item.itemID) },
            onMove: { start in model.moveMask(item.itemID, toStart: start) },
            onResizeStart: { model.resizeMask(item.itemID, start: model.sourceTime(inClip: index, atOutput: time($0))) },
            onResizeEnd: { model.resizeMask(item.itemID, end: model.sourceTime(inClip: index, atOutput: time($0))) })
    }

    // MARK: Playhead

    private var playhead: some View {
        PlayheadMarker(clock: model.clock, leading: Self.leading, pixelsPerSecond: pps)
            .allowsHitTesting(false)
    }
}

/// A thin grab area at the edge of a block, for trimming. `onDrag` receives the x position in the timeline.
private struct EdgeHandle: View {
    let onDrag: (CGFloat) -> Void

    var body: some View {
        Rectangle().fill(Color.white.opacity(0.001))
            .frame(width: 10)
            .overlay(Capsule().fill(Color.white.opacity(0.7)).frame(width: 3, height: 18))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("timeline")).onChanged { onDrag($0.location.x) })
            .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
    }
}

/// A zoom or blur on the timeline: drag the body to move it, drag either end to change its length.
private struct RangeBlock: View {
    let color: Color
    let icon: String
    let label: String
    let selected: Bool
    let dimmed: Bool
    let x: CGFloat
    let top: CGFloat
    let width: CGFloat
    let height: CGFloat
    let pixelsPerSecond: Double
    let showsStartHandle: Bool
    let showsEndHandle: Bool
    /// Where the zoom or blur starts in its recording, and how fast its clip plays, to turn a drag into a new start.
    let start: Double
    let speed: Double
    let onSelect: () -> Void
    /// Called while dragging the body, with the new start in the recording's seconds.
    let onMove: (Double) -> Void
    let onResizeStart: (CGFloat) -> Void
    let onResizeEnd: (CGFloat) -> Void

    /// The start when the drag began. The drag's distance is always measured from where it began, so it is added
    /// to this, not to a start that has already moved.
    @State private var dragOrigin: Double?

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(colors: [color.opacity(dimmed ? 0.2 : (selected ? 1 : 0.78)), color.opacity(dimmed ? 0.14 : (selected ? 0.86 : 0.62))],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected ? Color(fluidHex: 0xDCE6F7) : Color.white.opacity(0.14), lineWidth: selected ? 2 : 1))
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9.5, weight: .bold))
                Text(label).font(.system(size: 10, weight: .bold).monospacedDigit())
            }
            .foregroundStyle(.black.opacity(dimmed ? 0.4 : 0.72))
            .padding(.leading, showsStartHandle ? 12 : 6)
            .lineLimit(1)
            .allowsHitTesting(false)
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named("timeline")).onChanged { value in
            if dragOrigin == nil {
                dragOrigin = start
                onSelect()
            }
            onMove((dragOrigin ?? start) + Double(value.translation.width) / pixelsPerSecond * speed)
        }.onEnded { _ in dragOrigin = nil })
        .simultaneousGesture(TapGesture().onEnded { onSelect() })
        .overlay(alignment: .leading) { if showsStartHandle { EdgeHandle(onDrag: onResizeStart) } }
        .overlay(alignment: .trailing) { if showsEndHandle { EdgeHandle(onDrag: onResizeEnd) } }
        .offset(x: x, y: top)
    }
}

/// A clip's filmstrip: stills of its recording laid side by side, each showing the moment under it.
private struct ClipFilmstrip: View {
    let strip: Filmstrip?
    let sourceStart: Double
    let speed: Double
    let pixelsPerSecond: Double
    let aspect: Double
    let tint: Color

    var body: some View {
        Canvas { context, size in
            guard let strip, size.width > 0, size.height > 0 else { return }
            let tile = max(24, size.height * aspect)
            var x: CGFloat = 0
            while x < size.width {
                let sourceTime = sourceStart + Double(x + tile / 2) / pixelsPerSecond * speed
                if let image = strip.image(at: sourceTime) {
                    context.draw(Image(decorative: image, scale: 1), in: CGRect(x: x, y: 0, width: tile, height: size.height))
                }
                x += tile
            }
        }
        .background(LinearGradient(colors: [tint.opacity(0.55), tint.opacity(0.3)], startPoint: .top, endPoint: .bottom))
    }
}
