import AppKit
import Combine
import GlideCore
import SwiftUI

/// What is being placed on the video.
enum StageMode: Equatable {
    case crop
    case masks
    case zoom(UUID)
}

/// Editing directly on the video: the whole recording as it was captured, with what is being placed drawn on it.
/// Everything is in fractions of the display, the same as what the renderer reads, so what lands here lands in the video.
struct PreviewStage: View {
    @ObservedObject var model: EditorModel
    let mode: StageMode
    let finish: () -> Void

    @State private var poster: CGImage?
    @State private var painted: CGImage?
    @State private var drawing: CGRect?
    @State private var location: TimeMap.Location?

    private static let cropPresets: [(String, Double?)] = [("Full", nil), ("16:9", 16.0 / 9), ("4:3", 4.0 / 3), ("1:1", 1), ("9:16", 9.0 / 16)]

    private var source: UUID? {
        if case .zoom(let id) = mode { return model.source(ofZoom: id) }
        return location?.segment.sourceID
    }

    /// The moment to show: the playhead, unless a zoom is being placed and the playhead isn't inside it.
    private var sourceTime: Double {
        if case .zoom(let id) = mode, let zoom = model.project.zoom(id) {
            if let location, location.segment.sourceID == source, location.sourceTime >= zoom.start, location.sourceTime <= zoom.end {
                return location.sourceTime
            }
            return (zoom.start + zoom.end) / 2
        }
        return location?.sourceTime ?? 0
    }

    private var masks: [MaskRegion] { model.project.masks(of: source) }
    private var showingMasks: [MaskRegion] { masks.filter { !$0.isDisabled && sourceTime >= $0.start && sourceTime <= $0.end } }
    private var displayAspect: Double {
        let manifest = (model.sources.bundle(source) ?? model.bundle).manifest
        return manifest.displayWidth / manifest.displayHeight
    }

    var body: some View {
        ZStack {
            Theme.panel
            ZStack {
                if let picture = painted ?? poster {
                    Image(decorative: picture, scale: 1).resizable()
                } else {
                    Theme.track
                }
                GeometryReader { geometry in
                    canvas(size: geometry.size).coordinateSpace(name: StageCanvas.space)
                }
            }
            .aspectRatio(displayAspect, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(alignment: .top) { if mode == .crop { cropBar.padding(.top, 8) } }
        }
        .onReceive(model.clock.$time) { _ in
            let now = model.playheadLocation
            if now?.sourceTime != location?.sourceTime || now?.segment.sourceID != location?.segment.sourceID { location = now }
        }
        .task(id: "\(source?.uuidString ?? "main")-\(Int((sourceTime * 2).rounded()))") {
            poster = await model.posterFrame(source: source, atSource: sourceTime)
        }
        .task(id: PaintKey(poster: poster.map { ObjectIdentifier($0) }, masks: mode == .masks ? showingMasks : [])) {
            // Crop and zoom are placed on the plain recording; only masks change the picture.
            guard mode == .masks, let poster else { painted = nil; return }
            let showing = showingMasks, time = sourceTime
            let result = await Task.detached(priority: .userInitiated) { MaskPainter.paint(poster, masks: showing, time: time) }.value
            if !Task.isCancelled { painted = result }
        }
        .onChange(of: model.selection) { _, selection in
            // A mask picked on the timeline is only on the video while it is showing.
            if case .mask(let id) = selection, let mask = model.project.mask(id), !showingMasks.contains(where: { $0.id == id }) {
                model.seek(toSource: mask.start + 0.01, of: model.source(ofMask: id))
            }
        }
        .onExitCommand(perform: mode == .crop ? finish : nil)
    }

    private struct PaintKey: Equatable {
        let poster: ObjectIdentifier?
        let masks: [MaskRegion]
    }

    @ViewBuilder
    private func canvas(size: CGSize) -> some View {
        switch mode {
        case .crop:
            StageRect(rect: Binding(get: { model.project.settings.style.crop },
                                    set: { new in model.edit(coalescing: "crop") { $0.settings.style.crop = new } }),
                      size: size, minimum: CropRect.minimumSize, dimsOutside: true, showsThirds: true)
        case .masks:
            masksCanvas(size: size)
        case .zoom(let id):
            if let zoom = model.project.zoom(id) { zoomCanvas(zoom, size: size) }
        }
    }

    // MARK: Masks

    private func masksCanvas(size: CGSize) -> some View {
        let selected: UUID? = { if case .mask(let id) = model.selection { return id } else { return nil } }()
        return ZStack(alignment: .topLeading) {
            // Dragging on bare video draws a new area; a click there lets go of the selected one.
            Color.white.opacity(0.001)
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(StageCanvas.space))
                    .onChanged { value in
                        drawing = CGRect(x: min(value.startLocation.x, value.location.x), y: min(value.startLocation.y, value.location.y),
                                         width: abs(value.location.x - value.startLocation.x), height: abs(value.location.y - value.startLocation.y))
                            .intersection(CGRect(origin: .zero, size: size))
                    }
                    .onEnded { _ in
                        defer { drawing = nil }
                        guard let drawn = drawing, drawn.width > 6, drawn.height > 6 else {
                            model.selection = .none
                            return
                        }
                        model.addMaskAtPlayhead(rect: CropRect(x: drawn.minX / size.width, y: drawn.minY / size.height,
                                                               width: drawn.width / size.width, height: drawn.height / size.height)
                            .clamped(minimum: MaskRegion.minimumSize))
                    })

            ForEach(showingMasks) { mask in
                if mask.id == selected {
                    StageRect(rect: Binding(get: { model.project.mask(mask.id)?.rect ?? mask.rect },
                                            set: { new in model.updateMask(mask.id, key: "rect") { $0.rect = new } }),
                              size: size, minimum: MaskRegion.minimumSize)
                } else {
                    let frame = StageCanvas.frame(of: mask.rect, in: size)
                    Rectangle().strokeBorder(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .contentShape(Rectangle())
                        .frame(width: frame.width, height: frame.height)
                        .onTapGesture { model.selection = .mask(mask.id) }
                        .offset(x: frame.minX, y: frame.minY)
                }
            }

            if let drawing {
                Rectangle().fill(Color.white.opacity(0.15))
                    .overlay(Rectangle().stroke(Color.white, lineWidth: 1.5))
                    .frame(width: drawing.width, height: drawing.height)
                    .offset(x: drawing.minX, y: drawing.minY)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: Zoom

    /// The part of the screen the zoom shows, as a frame to drag: the middle moves it and the corners set how far it goes in.
    private func zoomCanvas(_ zoom: ZoomSegment, size: CGSize) -> some View {
        let crop = model.project.settings.style.crop
        let width = crop.width / zoom.scale, height = crop.height / zoom.scale
        let shown = CropRect(x: min(max(zoom.focusX - width / 2, crop.x), crop.x + crop.width - width),
                             y: min(max(zoom.focusY - height / 2, crop.y), crop.y + crop.height - height),
                             width: width, height: height)
        let frame = StageCanvas.frame(of: shown, in: size)
        return ZStack(alignment: .topLeading) {
            StageRect(rect: Binding(get: { shown }, set: { new in
                          model.updateZoom(zoom.id, key: "aim") {
                              $0.scale = min(max(crop.width / new.width, 1.2), 5)
                              $0.focusX = new.x + new.width / 2
                              $0.focusY = new.y + new.height / 2
                          }
                      }),
                      size: size, minimum: crop.width / 5, dimsOutside: true, keepsShape: true)
            Text(String(format: "%.1f×", zoom.scale))
                .font(Fluid.font(.caption, .semibold, monospacedDigits: true))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.7), in: Capsule())
                .offset(x: frame.minX + 6, y: frame.minY + 6)
                .allowsHitTesting(false)
        }
    }

    // MARK: Crop

    private var cropBar: some View {
        HStack(spacing: 2) {
            ForEach(Self.cropPresets, id: \.0) { name, ratio in
                FluidButton(name, variant: .ghost) { apply(preset: ratio) }
            }
            FluidButton("Done", icon: "checkmark", variant: .primary) { finish() }
                .keyboardShortcut(.return, modifiers: [])
                .padding(.leading, 4)
        }
        .padding(4)
        .fluidSurface(4, radius: Fluid.Radius.container)
    }

    /// The biggest rectangle of the chosen shape that fits on the screen, in the middle.
    private func apply(preset ratio: Double?) {
        guard let ratio else { return model.edit { $0.settings.style.crop = .full } }
        let width = ratio > displayAspect ? 1 : ratio / displayAspect
        let height = ratio > displayAspect ? displayAspect / ratio : 1
        model.edit { $0.settings.style.crop = CropRect(x: (1 - width) / 2, y: (1 - height) / 2, width: width, height: height) }
    }
}

enum StageCanvas {
    static let space = "stage-canvas"

    static func frame(of rect: CropRect, in size: CGSize) -> CGRect {
        CGRect(x: rect.x * size.width, y: rect.y * size.height, width: rect.width * size.width, height: rect.height * size.height)
    }
}

/// A rectangle on the video to drag: the inside moves it, and its corners and edges resize it. With `keepsShape` only the
/// corners do, and the rectangle stays the shape of the screen.
struct StageRect: View {
    @Binding var rect: CropRect
    let size: CGSize
    var minimum: Double
    var dimsOutside = false
    var showsThirds = false
    var keepsShape = false

    @State private var grab: Grab?

    /// Which sides of the rectangle a drag moves.
    private struct Grab {
        let start: CropRect
        var left = false, right = false, top = false, bottom = false
    }

    private static let reach: CGFloat = 10

    var body: some View {
        let frame = StageCanvas.frame(of: rect, in: size)
        ZStack(alignment: .topLeading) {
            if dimsOutside {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: size))
                    path.addRect(frame)
                }
                .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
            }
            ZStack {
                Rectangle().stroke(Color.white, lineWidth: 1.5)
                if showsThirds {
                    Path { path in
                        for part in [1.0 / 3, 2.0 / 3] {
                            path.move(to: CGPoint(x: frame.width * part, y: 0))
                            path.addLine(to: CGPoint(x: frame.width * part, y: frame.height))
                            path.move(to: CGPoint(x: 0, y: frame.height * part))
                            path.addLine(to: CGPoint(x: frame.width, y: frame.height * part))
                        }
                    }
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                }
            }
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
            .allowsHitTesting(false)

            ForEach(grips(of: frame), id: \.x) { point in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.5), radius: 1.5)
                    .frame(width: 9, height: 9)
                    .position(point.point)
                    .allowsHitTesting(false)
            }

            Color.white.opacity(0.001)
                .frame(width: frame.width + Self.reach * 2, height: frame.height + Self.reach * 2)
                .offset(x: frame.minX - Self.reach, y: frame.minY - Self.reach)
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(StageCanvas.space))
                    .onChanged { value in drag(value) }
                    .onEnded { _ in grab = nil })
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func grips(of frame: CGRect) -> [GripPoint] {
        var points = [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY),
                      CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: frame.maxX, y: frame.maxY)]
        if !keepsShape {
            points += [CGPoint(x: frame.midX, y: frame.minY), CGPoint(x: frame.midX, y: frame.maxY),
                       CGPoint(x: frame.minX, y: frame.midY), CGPoint(x: frame.maxX, y: frame.midY)]
        }
        return points.enumerated().map { GripPoint(x: $0.offset, point: $0.element) }
    }

    private func drag(_ value: DragGesture.Value) {
        if grab == nil { grab = grabbing(at: value.startLocation) }
        guard let grab else { return }
        let dx = (value.location.x - value.startLocation.x) / size.width
        let dy = (value.location.y - value.startLocation.y) / size.height
        let start = grab.start
        var left = start.x, right = start.x + start.width, top = start.y, bottom = start.y + start.height

        if !(grab.left || grab.right || grab.top || grab.bottom) {
            rect = CropRect(x: min(max(start.x + dx, 0), 1 - start.width), y: min(max(start.y + dy, 0), 1 - start.height),
                            width: start.width, height: start.height)
            return
        }
        if keepsShape {
            // The opposite corner stays put, and the drag sets the width.
            let width = min(max(grab.right ? start.width + dx : start.width - dx, minimum), grab.right ? 1 - start.x : start.x + start.width)
            let height = min(width * start.height / start.width, grab.bottom ? 1 - start.y : start.y + start.height)
            let kept = height * start.width / start.height
            rect = CropRect(x: grab.right ? start.x : start.x + start.width - kept, y: grab.bottom ? start.y : start.y + start.height - height,
                            width: kept, height: height)
            return
        }
        if grab.left { left = min(max(start.x + dx, 0), right - minimum) }
        if grab.right { right = max(min(start.x + start.width + dx, 1), left + minimum) }
        if grab.top { top = min(max(start.y + dy, 0), bottom - minimum) }
        if grab.bottom { bottom = max(min(start.y + start.height + dy, 1), top + minimum) }
        rect = CropRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    private func grabbing(at point: CGPoint) -> Grab {
        let frame = StageCanvas.frame(of: rect, in: size)
        var grab = Grab(start: rect)
        let nearLeft = abs(point.x - frame.minX) < Self.reach, nearRight = abs(point.x - frame.maxX) < Self.reach
        let nearTop = abs(point.y - frame.minY) < Self.reach, nearBottom = abs(point.y - frame.maxY) < Self.reach
        if keepsShape {
            guard (nearLeft || nearRight) && (nearTop || nearBottom) else { return grab }
        }
        grab.left = nearLeft
        grab.right = nearRight && !nearLeft
        grab.top = nearTop
        grab.bottom = nearBottom && !nearTop
        return grab
    }

    private struct GripPoint: Hashable {
        let x: Int
        let point: CGPoint
        static func == (a: GripPoint, b: GripPoint) -> Bool { a.x == b.x }
        func hash(into hasher: inout Hasher) { hasher.combine(x) }
    }
}
