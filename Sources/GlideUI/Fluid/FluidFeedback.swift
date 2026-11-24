import SwiftUI

// Fluid Functionalism's Badge, Banner, Tooltip, Card list, CarouselDots, ThinkingIndicator and ThinkingSteps.
// Ported from the MIT-licensed originals by Micka Touillaud.

// MARK: Badge

enum FluidBadgeColor {
    case gray, red, orange, amber, yellow, lime, green, emerald, teal, cyan, blue, indigo, violet, purple, fuchsia, pink, rose

    var hue: Color {
        switch self {
        case .gray: return Fluid.mutedForeground
        case .red: return Color(fluidHex: 0xEF4444)
        case .orange: return Color(fluidHex: 0xF97316)
        case .amber: return Color(fluidHex: 0xF59E0B)
        case .yellow: return Color(fluidHex: 0xEAB308)
        case .lime: return Color(fluidHex: 0x84CC16)
        case .green: return Color(fluidHex: 0x22C55E)
        case .emerald: return Color(fluidHex: 0x10B981)
        case .teal: return Color(fluidHex: 0x14B8A6)
        case .cyan: return Color(fluidHex: 0x06B6D4)
        case .blue: return Color(fluidHex: 0x3B82F6)
        case .indigo: return Color(fluidHex: 0x6366F1)
        case .violet: return Color(fluidHex: 0x8B5CF6)
        case .purple: return Color(fluidHex: 0xA855F7)
        case .fuchsia: return Color(fluidHex: 0xD946EF)
        case .pink: return Color(fluidHex: 0xEC4899)
        case .rose: return Color(fluidHex: 0xF43F5E)
        }
    }

    /// The solid badge's fill: the hue at 15% over the page background (gray uses the neutral accent).
    var tint: Color { self == .gray ? Fluid.accent : Fluid.background.mix(with: hue, by: 0.15) }
}

/// A small label. Solid badges are tinted with their color; dot badges are outlined with a colored dot.
struct FluidBadge: View {
    let text: String
    var color: FluidBadgeColor = .gray
    var dot = false
    var density: Fluid.Density = .compact

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Fluid.Radius.item, style: .continuous)
        HStack(spacing: density == .compact ? 4 : 6) {
            if dot {
                Circle().fill(color == .gray ? Fluid.mutedForeground : color.hue)
                    .frame(width: density == .compact ? 6 : 7, height: density == .compact ? 6 : 7)
            }
            Text(text).font(Fluid.font(.caption, density: density, monospacedDigits: true))
        }
        .foregroundStyle(Fluid.foreground)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, density == .compact ? 8 : 10)
        .frame(height: density == .compact ? 20 : 24)
        .background(dot ? Color.clear : color.tint, in: shape)
        .overlay { if dot { shape.strokeBorder(Fluid.border, lineWidth: 1) } }
    }
}

// MARK: Banner

enum FluidBannerStatus {
    case neutral, info, success, warning, error

    var tone: Color {
        switch self {
        case .neutral: return Fluid.foreground
        case .info: return Fluid.info
        case .success: return Fluid.success
        case .warning: return Fluid.warning
        case .error: return Fluid.destructive
        }
    }
}

/// A message on a soft wash: a status glyph in its tone, a title, an optional description and actions, and an
/// optional ✕. It opens by growing its row while it springs up from smaller, and on dismiss it fades and shrinks so it
/// is gone by the time the space is 60% closed.
struct FluidBanner<Actions: View>: View {
    var status: FluidBannerStatus = .neutral
    let title: String
    var message: String?
    var highContrast = false
    var density: Fluid.Density = .compact
    var onDismiss: (() -> Void)?
    @ViewBuilder var actions: Actions

    @State private var hoveredClose = false

    var body: some View {
        let compact = density == .compact
        let fill = highContrast ? status.tone.opacity(status == .neutral ? 0.08 : 0.12) : Fluid.hover
        HStack(alignment: message == nil ? .center : .top, spacing: 0) {
            FluidStatusGlyph(status: status, size: compact ? 16 : 20)
                .frame(height: compact ? 18 : 20)
                .padding(.trailing, compact ? 10 : 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Fluid.font(.subtitle, .semibold, density: density))
                if let message {
                    Text(message).font(Fluid.font(.subtitle, density: density)).fixedSize(horizontal: false, vertical: true)
                }
                if message != nil, Actions.self != EmptyView.self {
                    HStack(spacing: 8) { actions }.padding(.top, compact ? 6 : 8)
                }
            }
            .foregroundStyle(Fluid.foreground)
            .frame(maxWidth: .infinity, alignment: .leading)
            if message == nil, Actions.self != EmptyView.self {
                HStack(spacing: 8) { actions }.padding(.leading, compact ? 10 : 12).padding(.vertical, compact ? -5 : -4)
            }
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: compact ? 11 : 12, weight: hoveredClose ? .semibold : .regular))
                        .foregroundStyle(hoveredClose ? Fluid.foreground : Fluid.mutedForeground)
                        .frame(width: 28, height: 28)
                        .background(hoveredClose ? Fluid.hover : .clear, in: RoundedRectangle(cornerRadius: Fluid.Radius.item))
                }
                .buttonStyle(.plain)
                .onHover { hoveredClose = $0 }
                .padding(.leading, compact ? 6 : 8)
                .padding(.trailing, -6)
                .padding(.vertical, compact ? -5 : -4)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(compact ? 12 : 16)
        .background(fill, in: RoundedRectangle(cornerRadius: Fluid.Radius.container, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

extension FluidBanner where Actions == EmptyView {
    init(status: FluidBannerStatus = .neutral, title: String, message: String? = nil, highContrast: Bool = false,
         density: Fluid.Density = .compact, onDismiss: (() -> Void)? = nil) {
        self.init(status: status, title: title, message: message, highContrast: highContrast, density: density,
                  onDismiss: onDismiss, actions: { EmptyView() })
    }
}

/// The banner's status glyphs: a filled disc (or triangle for warnings) with the mark cut out of it.
struct FluidStatusGlyph: View {
    let status: FluidBannerStatus
    var size: CGFloat = 16

    var body: some View {
        Canvas { context, canvas in
            let s = canvas.width / 24
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            let markStyle = StrokeStyle(lineWidth: 2.25 * s, lineCap: .round, lineJoin: .round)
            var mark = Path()
            switch status {
            case .neutral:
                // The outline info glyph.
                context.stroke(Path(ellipseIn: CGRect(x: 2 * s, y: 2 * s, width: 20 * s, height: 20 * s)),
                               with: .color(Fluid.foreground), lineWidth: 1.5 * s)
                var line = Path()
                line.move(to: p(12, 16)); line.addLine(to: p(12, 11))
                line.move(to: p(12, 7.5)); line.addLine(to: p(12.01, 7.5))
                context.stroke(line, with: .color(Fluid.foreground), style: StrokeStyle(lineWidth: 1.5 * s, lineCap: .round))
                return
            case .warning:
                var triangle = Path()
                triangle.move(to: p(21.73, 18)); triangle.addLine(to: p(13.73, 4))
                triangle.addQuadCurve(to: p(10.27, 4), control: p(12, 1.2))
                triangle.addLine(to: p(2.27, 18))
                triangle.addQuadCurve(to: p(4, 21), control: p(1.2, 21))
                triangle.addLine(to: p(20, 21))
                triangle.addQuadCurve(to: p(21.73, 18), control: p(22.8, 21))
                triangle.closeSubpath()
                context.fill(triangle, with: .color(status.tone))
                context.stroke(triangle, with: .color(status.tone), style: StrokeStyle(lineWidth: 1.5 * s, lineJoin: .round))
                mark.move(to: p(12, 9.5)); mark.addLine(to: p(12, 13))
                mark.move(to: p(12, 17)); mark.addLine(to: p(12.01, 17))
            case .success:
                context.fill(Path(ellipseIn: CGRect(x: 1.5 * s, y: 1.5 * s, width: 21 * s, height: 21 * s)), with: .color(status.tone))
                mark.move(to: p(8.5, 12.25)); mark.addLine(to: p(11, 14.75)); mark.addLine(to: p(15.5, 9.75))
            case .info:
                context.fill(Path(ellipseIn: CGRect(x: 1.5 * s, y: 1.5 * s, width: 21 * s, height: 21 * s)), with: .color(status.tone))
                mark.move(to: p(12, 16.5)); mark.addLine(to: p(12, 11.5))
                mark.move(to: p(12, 7.5)); mark.addLine(to: p(12.01, 7.5))
            case .error:
                context.fill(Path(ellipseIn: CGRect(x: 1.5 * s, y: 1.5 * s, width: 21 * s, height: 21 * s)), with: .color(status.tone))
                mark.move(to: p(12, 7.5)); mark.addLine(to: p(12, 12.5))
                mark.move(to: p(12, 16.5)); mark.addLine(to: p(12.01, 16.5))
            }
            context.stroke(mark, with: .color(Fluid.background), style: markStyle)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: Tooltip

enum FluidTooltipSide { case top, bottom, leading }

extension View {
    /// Fluid's tooltip: an inverted caption chip 8 pt from the view, after a 200 ms hover. Once one has shown,
    /// moving to a neighbour within 300 ms opens its tooltip at once.
    func fluidTooltip(_ text: String?, side: FluidTooltipSide = .top) -> some View {
        modifier(FluidTooltipModifier(text: text, side: side))
    }
}

@MainActor
private enum FluidTooltipClock {
    static var lastClosed = Date.distantPast
}

private struct FluidTooltipModifier: ViewModifier {
    let text: String?
    let side: FluidTooltipSide
    @State private var shown = false
    @State private var pending: Task<Void, Never>?

    func body(content: Content) -> some View {
        if let text, !text.isEmpty {
            content
                .onHover { inside in
                    pending?.cancel()
                    if inside {
                        let skipDelay = Date().timeIntervalSince(FluidTooltipClock.lastClosed) < 0.3
                        pending = Task { @MainActor in
                            if !skipDelay { try? await Task.sleep(for: .milliseconds(200)) }
                            if !Task.isCancelled { shown = true }
                        }
                    } else if shown {
                        shown = false
                        FluidTooltipClock.lastClosed = Date()
                    }
                }
                .simultaneousGesture(TapGesture().onEnded { pending?.cancel(); shown = false })
                .fluidPopup(isPresented: $shown, placement: side == .top ? .above : (side == .leading ? .leading : .below), offset: 8, interactive: false,
                            inset: FluidTooltipBubble.inset) {
                    FluidTooltipBubble(text: text, side: side)
                }
                .accessibilityHint(text)
        } else {
            content
        }
    }
}

struct FluidTooltipBubble: View {
    let text: String
    var side: FluidTooltipSide = .top
    @State private var appeared = false

    static let inset: CGFloat = 6

    var body: some View {
        Text(text)
            .font(Fluid.font(.caption, density: .regular))
            .foregroundStyle(Fluid.background)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Fluid.foreground, in: RoundedRectangle(cornerRadius: Fluid.Radius.item, style: .continuous))
            .fixedSize()
            .padding(Self.inset)
            // It drifts 4 pt away from the view as it fades in.
            .offset(x: appeared || side != .leading ? 0 : 4, y: appeared || side == .leading ? 0 : (side == .top ? 4 : -4))
            .opacity(appeared ? 1 : 0)
            .onAppear { withAnimation(Fluid.Motion.fast) { appeared = true } }
    }
}

// MARK: Card list

/// A group of cards in Fluid's default style: no frame of their own, hairline dividers between them, and one hover
/// highlight that travels to the card nearest the pointer. The selected card sits on an `active` fill, and the
/// hairlines touching the lit or selected card disappear.
struct FluidCardList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    var selection: Item.ID?
    var density: Fluid.Density = .compact
    var onSelect: ((Item) -> Void)?
    @ViewBuilder var row: (Item, _ isSelected: Bool, _ isLit: Bool) -> Row

    @State private var space = "fluid-cards-\(UUID().uuidString)"
    @State private var frames: [Item.ID: CGRect] = [:]
    @State private var lit: Item.ID?
    @State private var litRect: CGRect?
    @State private var litOpacity = 0.0

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let selected = selection == item.id
                let next = index + 1 < items.count ? items[index + 1].id : nil
                let hideRule = index == items.count - 1 || [item.id, next].contains { $0 != nil && ($0 == lit || $0 == selection) }
                row(item, selected, lit == item.id)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: Fluid.Radius.container, style: .continuous).fill(Fluid.active)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if !hideRule { Rectangle().fill(Fluid.divider).frame(height: 1) }
                    }
                    .contentShape(Rectangle())
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(space)) } action: { frames[item.id] = $0 }
                    .onTapGesture { onSelect?(item) }
            }
        }
        .background(alignment: .topLeading) {
            if let litRect, onSelect != nil {
                RoundedRectangle(cornerRadius: Fluid.Radius.container, style: .continuous)
                    .fill(Fluid.hover)
                    .frame(width: litRect.width, height: litRect.height)
                    .offset(x: litRect.minX, y: litRect.minY)
                    .opacity(litOpacity)
                    .allowsHitTesting(false)
            }
        }
        .coordinateSpace(name: space)
        .onContinuousHover(coordinateSpace: .named(space)) { phase in
            guard onSelect != nil else { return }
            switch phase {
            case .active(let point):
                let id = items.first { frames[$0.id].map { $0.minY <= point.y && point.y <= $0.maxY } ?? false }?.id
                    ?? items.min { abs((frames[$0.id]?.midY ?? .infinity) - point.y) < abs((frames[$1.id]?.midY ?? .infinity) - point.y) }?.id
                guard id != lit, let id, let rect = frames[id] else { return }
                let fresh = lit == nil || litOpacity == 0
                lit = id
                if fresh {
                    var still = Transaction(animation: nil)
                    still.disablesAnimations = true
                    withTransaction(still) { litRect = rect }
                    withAnimation(.linear(duration: 0.08)) { litOpacity = 1 }
                } else {
                    withAnimation(Fluid.Motion.fast) { litRect = rect }
                }
            case .ended:
                lit = nil
                withAnimation(Fluid.Motion.fastExit) { litOpacity = 0 }
            }
        }
    }
}

/// The standard content of a card in a list: an optional icon tile, a title that turns semibold when selected, a
/// muted description, and trailing content.
struct FluidCardRow<Trailing: View>: View {
    let title: String
    var detail: String?
    var icon: String?
    var iconTint: Color?
    var isSelected = false
    var density: Fluid.Density = .compact
    @ViewBuilder var trailing: Trailing

    var body: some View {
        let compact = density == .compact
        HStack(spacing: compact ? 10 : 12) {
            if let icon {
                FluidIconTile(icon: icon, size: compact ? 32 : 38, isLit: isSelected, tint: iconTint)
            }
            VStack(alignment: .leading, spacing: 2) {
                ZStack(alignment: .leading) {
                    Text(title).font(Fluid.font(.subtitle, .semibold, density: density)).hidden()
                    Text(title).font(Fluid.font(.subtitle, isSelected ? .semibold : .normal, density: density))
                }
                .foregroundStyle(Fluid.foreground)
                .lineLimit(1)
                if let detail {
                    Text(detail).font(Fluid.font(.caption, density: density)).foregroundStyle(Fluid.mutedForeground).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, compact ? 10 : 12)
        .padding(.vertical, compact ? 8 : 10)
        .animation(.easeOut(duration: 0.08), value: isSelected)
    }
}

extension FluidCardRow where Trailing == EmptyView {
    init(title: String, detail: String? = nil, icon: String? = nil, iconTint: Color? = nil, isSelected: Bool = false,
         density: Fluid.Density = .compact) {
        self.init(title: title, detail: detail, icon: icon, iconTint: iconTint, isSelected: isSelected, density: density,
                  trailing: { EmptyView() })
    }
}

// MARK: CarouselDots

/// A row of dots for paging: the current one stretches into a pill, filled from the left while `progress` runs.
struct FluidCarouselDots: View {
    let count: Int
    @Binding var index: Int
    var progress: Double = 1

    @State private var hovered: Int?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                let current = i == index
                let width: CGFloat = current ? 24 : 6
                Capsule()
                    .fill(Fluid.foreground.opacity(0.15))
                    .frame(width: width, height: 6)
                    .overlay(alignment: .leading) {
                        if current {
                            // Slid in, never scaled, so its round end stays round.
                            Capsule().fill(Fluid.foreground.opacity(0.4))
                                .frame(width: width, height: 6)
                                .offset(x: CGFloat(progress - 1) * (width - 6))
                        }
                    }
                    .clipShape(Capsule())
                    .padding(6)
                    .background(Capsule().fill(hovered == i ? Fluid.hover : .clear))
                    .contentShape(Capsule())
                    .onHover { if $0 { hovered = i } else if hovered == i { hovered = nil } }
                    .onTapGesture { index = i }
                    .accessibilityLabel("Go to slide \(i + 1)")
                    .accessibilityAddTraits(current ? [.isButton, .isSelected] : .isButton)
            }
        }
        .animation(Fluid.Motion.moderate, value: index)
        .animation(Fluid.Motion.fast, value: hovered)
    }
}

// MARK: Shimmer

/// Text with a lighter band sweeping across it from right to left every 1.5 s, used for work in progress.
struct FluidShimmerText: View {
    let text: String
    var font: Font = Fluid.font(.body, density: .regular)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SwiftUI.TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.5) / 1.5
            let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            // The gradient is three times the text's width; its band centre runs from 1.5 widths to −0.5.
            let start = -2 * eased
            Text(text)
                .font(font)
                .foregroundStyle(LinearGradient(stops: [
                    .init(color: Fluid.accent, location: 0.35),
                    .init(color: Fluid.mutedForeground, location: 0.5),
                    .init(color: Fluid.accent, location: 0.65),
                ], startPoint: UnitPoint(x: start, y: 0.5), endPoint: UnitPoint(x: start + 3, y: 0.5)))
        }
    }
}

// MARK: ThinkingIndicator

/// Fluid's working indicator: a glyph morphing between a circle and an infinity sign, and a word that rolls over to
/// the next every 4 s, with the shimmer running across it.
struct FluidThinkingIndicator: View {
    var words = ["Thinking", "Planning", "Refining"]
    var density: Fluid.Density = .regular
    var showIcon = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0

    var body: some View {
        HStack(spacing: 8) {
            if showIcon {
                FluidMorphGlyph(still: reduceMotion)
                    .frame(width: density == .compact ? 18 : 20, height: density == .compact ? 18 : 20)
                    .foregroundStyle(Fluid.mutedForeground)
            }
            ZStack(alignment: .leading) {
                Text(words.max { $0.count < $1.count } ?? "").font(Fluid.font(.body, density: density)).hidden()
                FluidShimmerText(text: words[index % max(words.count, 1)], font: Fluid.font(.body, density: density))
                    .id(index)
                    .transition(.asymmetric(
                        insertion: .offset(y: 14).combined(with: .opacity).animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.24)),
                        removal: .offset(y: -14).combined(with: .opacity).animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.16))))
            }
            .clipped()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .task(id: words) {
            guard !reduceMotion, words.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                if Task.isCancelled { break }
                withAnimation { index += 1 }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(words.first ?? "Working")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// A path that morphs circle → ∞ → circle (the other way round) → ∞ over 6 s, all four shapes sharing one command
/// structure so the points interpolate.
struct FluidMorphGlyph: View {
    var still = false

    private static let circleA: [CGPoint] = points("12 8 14.21 8 16 9.79 16 12 16 14.21 14.21 16 12 16 9.79 16 8 14.21 8 12 8 9.79 9.79 8 12 8")
    private static let infinity: [CGPoint] = points("12 12 14 8.5 19 8.5 19 12 19 15.5 14 15.5 12 12 10 8.5 5 8.5 5 12 5 15.5 10 15.5 12 12")
    private static let circleB: [CGPoint] = points("12 16 14.21 16 16 14.21 16 12 16 9.79 14.21 8 12 8 9.79 8 8 9.79 8 12 8 14.21 9.79 16 12 16")

    private static func points(_ list: String) -> [CGPoint] {
        let numbers = list.split(separator: " ").compactMap { Double($0) }
        return stride(from: 0, to: numbers.count - 1, by: 2).map { CGPoint(x: numbers[$0], y: numbers[$0 + 1]) }
    }

    var body: some View {
        SwiftUI.TimelineView(.animation(paused: still)) { context in
            let shape: [CGPoint] = {
                if still { return Self.infinity }
                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6) / 6
                let stops = [Self.circleA, Self.infinity, Self.circleB, Self.infinity, Self.circleA]
                let quarter = min(Int(t * 4), 3)
                var p = t * 4 - Double(quarter)
                p = p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2
                return zip(stops[quarter], stops[quarter + 1]).map { a, b in
                    CGPoint(x: a.x + (b.x - a.x) * p, y: a.y + (b.y - a.y) * p)
                }
            }()
            Canvas { context, size in
                let s = size.width / 24
                func q(_ i: Int) -> CGPoint { CGPoint(x: shape[i].x * s, y: shape[i].y * s) }
                var path = Path()
                path.move(to: q(0))
                for c in 0..<4 { path.addCurve(to: q(3 * c + 3), control1: q(3 * c + 1), control2: q(3 * c + 2)) }
                path.closeSubpath()
                context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 1.5 * s, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

// MARK: ThinkingSteps

struct FluidStep: Identifiable, Equatable {
    enum Status { case pending, active, complete }
    let id: String
    var title: String
    var detail: String?
    var icon: String?
    var status: Status = .complete
}

/// A collapsible list of steps joined by a hairline rail. Each step grows in as it starts (slow spring, a little
/// bounce); the one in progress shimmers and trails an ellipsis. Pending steps aren't shown.
struct FluidThinkingSteps: View {
    var title = "Thinking"
    let steps: [FluidStep]
    var density: Fluid.Density = .regular
    @State private var open = true
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(Fluid.Motion.moderate) { open.toggle() } } label: {
                HStack(spacing: 10) {
                    ZStack(alignment: .leading) {
                        Text(title).font(Fluid.font(.body, .semibold, density: density)).hidden()
                        Text(title).font(Fluid.font(.body, open ? .semibold : .normal, density: density))
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: density == .compact ? 10 : 11, weight: hovered || open ? .semibold : .regular))
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .animation(Fluid.Motion.fast, value: open)
                }
                .foregroundStyle(open || hovered ? Fluid.foreground : Fluid.mutedForeground)
                .padding(.horizontal, density == .compact ? 10 : 12)
                .padding(.vertical, density == .compact ? 6 : 8)
                .background(Fluid.hover.opacity(hovered ? 1 : 0), in: RoundedRectangle(cornerRadius: Fluid.Radius.item))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { inside in withAnimation(inside ? .linear(duration: 0.08) : .linear(duration: 0.06)) { hovered = inside } }
            .accessibilityValue(open ? "expanded" : "collapsed")

            if open {
                VStack(alignment: .leading, spacing: 0) {
                    let shown = steps.filter { $0.status != .pending }
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, step in
                        stepRow(step, isLast: index == shown.count - 1)
                            .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.24).delay(0.08))
                                                        .combined(with: .move(edge: .top).animation(Fluid.Motion.slow)),
                                                    removal: .opacity.animation(Fluid.Motion.fastExit)))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 12)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Fluid.Motion.slow, value: steps)
    }

    private func stepRow(_ step: FluidStep, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 4) {
                Group {
                    if let icon = step.icon {
                        Image(systemName: icon).font(.system(size: density == .compact ? 10 : 11))
                    } else {
                        Circle().fill(Fluid.mutedForeground.opacity(0.6)).frame(width: 6, height: 6)
                    }
                }
                .foregroundStyle(Fluid.mutedForeground)
                .frame(width: 14, height: 14)
                .padding(.top, 2)
                if !isLast { Rectangle().fill(Fluid.divider).frame(width: 1).frame(maxHeight: .infinity) }
            }
            .frame(width: 14)
            VStack(alignment: .leading, spacing: 4) {
                if step.status == .active {
                    FluidShimmerText(text: step.title + "…", font: Fluid.font(.body, .semibold, density: density))
                } else {
                    Text(step.title).font(Fluid.font(.body, .semibold, density: density)).foregroundStyle(Fluid.foreground)
                }
                if let detail = step.detail {
                    Text(detail).font(Fluid.font(.body, density: density)).foregroundStyle(Fluid.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, isLast ? 0 : 6)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .fixedSize(horizontal: false, vertical: true)
    }
}
