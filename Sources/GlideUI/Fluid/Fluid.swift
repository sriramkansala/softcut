import AppKit
import SwiftUI

// Fluid Functionalism, ported to SwiftUI.
// Design system and components by Micka Touillaud, MIT License (see reference/fluid-registry/LICENSE):
// https://www.fluidfunctionalism.com, https://github.com/mickadesign/fluid-functionalism
//
// This file holds the foundations every component builds on: colors and surfaces, motion, type, sizes, shapes and
// the fluid hover. Glide is a dark app, so the dark values are the ones used.

/// The design tokens.
enum Fluid {
    // MARK: Color

    /// Layered surfaces, from the app's backdrop (1) up to the highest popover (8).
    static let surface1 = Color(fluidHex: 0x171717)
    static let surface2 = Color(fluidHex: 0x1E1E1E)
    static let surface3 = Color(fluidHex: 0x252525)
    static let surface4 = Color(fluidHex: 0x2C2C2C)
    static let surface5 = Color(fluidHex: 0x333333)
    static let surface6 = Color(fluidHex: 0x3A3A3A)
    static let surface7 = Color(fluidHex: 0x414141)
    static let surface8 = Color(fluidHex: 0x484848)

    static func surface(_ level: Int) -> Color {
        [surface1, surface2, surface3, surface4, surface5, surface6, surface7, surface8][min(max(level, 1), 8) - 1]
    }

    /// Interaction fills laid over a surface.
    static let hover = Color.white.opacity(0.06)
    static let active = Color.white.opacity(0.10)
    static let selected = Color(fluidHex: 0x525252)
    static let tint = Color.white.opacity(0.25)
    static let tintHover = Color.white.opacity(0.20)
    static let destructiveLight = Color(fluidHex: 0x450A0A)
    /// Fluid's `--focus-ring` (#6B97FF by default), themed to Glide's brand purple so the app has one accent.
    static let focusRing = Color(fluidHex: 0x8B70FF)

    /// Base colors, the dark values of the Fluid site's own theme.
    static let background = Color(fluidHex: 0x171717)
    static let foreground = Color(fluidHex: 0xF5F5F5)
    static let card = Color(fluidHex: 0x252525)
    static let muted = Color(fluidHex: 0x1E1E1E)
    static let mutedForeground = Color(fluidHex: 0xA3A3A3)
    /// A neutral highlight (the slider's hover preview, the off switch track).
    static let accent = Color(fluidHex: 0x525252)
    static let border = Color(fluidHex: 0xF5F5F5, opacity: 0.12)
    static let input = Color(fluidHex: 0x404040)
    static let destructive = Color(fluidHex: 0xFCA5A5)
    static let info = Color(fluidHex: 0x93C5FD)
    static let success = Color(fluidHex: 0x86EFAC)
    static let warning = Color(fluidHex: 0xFCD34D)
    /// A hairline at 60% of the border, for dividers between cards and rows.
    static let divider = Color(fluidHex: 0xF5F5F5, opacity: 0.072)
    /// The switch's on color, a little darker under the pointer.
    static let switchOn = Color(fluidHex: 0x7C5CFF)
    static let switchOnHover = Color(fluidHex: 0x6D4CF2)

    // MARK: Motion

    /// Motion tiers. The bigger the thing that moves, the slower the spring. Each tier enters with a spring and
    /// leaves with a quicker tween, so a dismissal reads as crisp and final.
    enum Motion {
        /// Highlights, small state changes.
        static let fast = Animation.spring(duration: 0.08, bounce: 0)
        static let fastExit = Animation.easeOut(duration: 0.06)
        /// Dropdowns, tabs, drawers, selection backgrounds: critically damped, lands exactly.
        static let moderate = Animation.spring(duration: 0.16, bounce: 0)
        static let moderateExit = Animation.easeOut(duration: 0.12)
        /// The largest things: a little bounce.
        static let slow = Animation.spring(duration: 0.24, bounce: 0.12)
        static let slowExit = Animation.easeOut(duration: 0.16)
        /// Fades of the hover highlight.
        static let fade = Animation.linear(duration: 0.08)
    }

    // MARK: Type

    /// The six type roles, each a size and a line height.
    enum TypeRole {
        case display, title, subtitle, body, caption, micro

        func size(_ density: Density) -> CGFloat {
            switch (self, density) {
            case (.display, .regular): return 28
            case (.display, .compact): return 24
            case (.title, .regular): return 16
            case (.title, .compact): return 15
            case (.subtitle, .regular): return 14
            case (.subtitle, .compact): return 13
            case (.body, .regular): return 13
            case (.body, .compact): return 12
            case (.caption, .regular): return 12
            case (.caption, .compact): return 11
            case (.micro, .regular): return 11
            case (.micro, .compact): return 10
            }
        }

        func leading(_ density: Density) -> CGFloat {
            switch (self, density) {
            case (.display, .regular): return 34
            case (.display, .compact): return 30
            case (.title, .regular): return 22
            case (.title, .compact): return 20
            case (.subtitle, .regular): return 20
            case (.subtitle, .compact): return 18
            case (.body, .regular): return 20
            case (.body, .compact): return 18
            case (.caption, .regular): return 16
            case (.caption, .compact): return 14
            case (.micro, .regular): return 14
            case (.micro, .compact): return 12
            }
        }
    }

    /// Text weights: normal for text, semibold for headings and selected items, bold for display only.
    enum Weight {
        case normal, semibold, bold

        /// The system font's weight scale, matched to Inter's 400 / 550 / 700.
        var native: NSFont.Weight {
            switch self {
            case .normal: return .regular
            case .semibold: return NSFont.Weight(0.265)
            case .bold: return .bold
            }
        }
    }

    static func font(_ role: TypeRole, _ weight: Weight = .normal, density: Density = .compact, monospacedDigits: Bool = false) -> Font {
        let base = NSFont.systemFont(ofSize: role.size(density), weight: weight.native)
        var font = Font(base)
        if monospacedDigits { font = font.monospacedDigit() }
        return font
    }

    // MARK: Size

    /// The size ladder. Regular is 36 pt controls; compact (28 pt) is for dense surfaces: toolbars, sidebars,
    /// inspectors.
    enum Density {
        case regular, compact

        /// Buttons, inputs, select triggers, subtle tabs, and list or menu rows, so a popup row lines up with the
        /// control that opened it.
        var control: CGFloat { self == .regular ? 36 : 28 }
        /// A tab inside a padded segmented list, and that list's padding: together they add up to `control`.
        var segmentItem: CGFloat { self == .regular ? 28 : 24 }
        var segmentPad: CGFloat { self == .regular ? 4 : 2 }
        /// Horizontal padding of bounded controls, and of rows inside a padded list.
        var paddingX: CGFloat { self == .regular ? 12 : 10 }
        var itemPaddingX: CGFloat { self == .regular ? 8 : 6 }
        /// Gap between a glyph and its label, and between neighbouring controls.
        var gap: CGFloat { self == .regular ? 8 : 4 }
        var icon: CGFloat { self == .regular ? 16 : 14 }
    }

    // MARK: Shape

    enum Radius {
        /// Items, buttons, inputs, hover and selection backgrounds.
        static let item: CGFloat = 8
        /// Containers: cards, popovers, segmented lists.
        static let container: CGFloat = 12
        static let focusRing: CGFloat = 10

        /// The radius for something inset inside a rounded container, so the two curves stay parallel.
        static func inset(in outer: CGFloat, by inset: CGFloat) -> CGFloat { max(0, outer - inset) }
    }
}

extension Color {
    init(fluidHex hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

// MARK: Surfaces

extension View {
    /// A raised surface at one of the eight levels: its fill, a hairline ring, a faint top highlight, and a drop
    /// shadow that deepens with the level.
    /// `shadow` overrides the shadow's level: popups keep a level-3 shadow whatever surface they open from.
    func fluidSurface(_ level: Int, radius: CGFloat = Fluid.Radius.container, shadow: Int? = nil) -> some View {
        modifier(FluidSurface(level: level, shadowLevel: shadow ?? level, radius: radius))
    }
}

/// The surface level a view sits on, so a popup or a raised pill can step up from it.
struct FluidSurfaceLevelKey: EnvironmentKey {
    static let defaultValue = 1
}

extension EnvironmentValues {
    var fluidSurfaceLevel: Int {
        get { self[FluidSurfaceLevelKey.self] }
        set { self[FluidSurfaceLevelKey.self] = newValue }
    }
}

private struct FluidSurface: ViewModifier {
    let level: Int
    let shadowLevel: Int
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let level = min(max(shadowLevel, 1), 8)
        // The dark theme's shadow-N, layer by layer: an inner ring and a top highlight that brighten with height, a
        // 1 pt dark ring outside (from level 3), and soft drops of 1, 3, 6, 12, 24, 48 and 96 pt. Each drop is
        // `0 Y Y -Y/2` in CSS: offset Y, blurred Y, and shrunk by half of Y on every side, so the deep layers only
        // show under large surfaces and vanish under small ones.
        let ring = level >= 6 ? 0.06 : (level >= 4 ? 0.04 : 0.02)
        let highlight = level >= 7 ? 0.06 : (level >= 5 ? 0.04 : (level >= 3 ? 0.02 : (level == 2 ? 0.01 : 0)))
        let outer = level >= 3 ? 0.12 + 0.02 * Double(level - 3) : 0
        let drops: [CGFloat] = Array([1, 3, 6, 12, 24, 48, 96].prefix(max(0, level - 1)))
        return content
            .background(Fluid.surface(self.level), in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(ring), lineWidth: 1))
            .overlay(alignment: .top) {
                if highlight > 0 {
                    shape.strokeBorder(Color.white.opacity(highlight), lineWidth: 1)
                        .mask(Rectangle().frame(height: 1.5).frame(maxHeight: .infinity, alignment: .top))
                }
            }
            .background {
                ZStack {
                    ForEach(drops, id: \.self) { y in
                        RoundedRectangle(cornerRadius: max(0, radius - y / 2), style: .continuous)
                            .fill(Color.black.opacity(0.18))
                            .padding(y / 2)
                            .offset(y: y)
                            .blur(radius: y / 2)
                    }
                    if outer > 0 {
                        RoundedRectangle(cornerRadius: radius + 1, style: .continuous)
                            .strokeBorder(Color.black.opacity(outer), lineWidth: 1)
                            .padding(-1)
                    }
                }
                .allowsHitTesting(false)
            }
    }
}

// MARK: Fluid hover

/// Fluid hover: in a group of items, the one nearest the pointer is highlighted, even when the pointer is in a gap
/// or the padding, so a click never falls between targets. One highlight springs from item to item (fast tier); it
/// fades in where the pointer enters and fades out when it leaves. A click anywhere in the group goes to the
/// highlighted item.
///
///     VStack { ForEach(rows) { row in RowView(row).fluidHoverItem(row.id) { pick(row) } } }
///         .fluidHoverGroup(axis: .vertical)
extension View {
    func fluidHoverGroup(axis: Axis? = .vertical, highlight: Color = Fluid.hover, radius: CGFloat = Fluid.Radius.item,
                         isEnabled: Bool = true) -> some View {
        modifier(FluidHoverGroup(axis: axis, highlight: highlight, radius: radius, isEnabled: isEnabled))
    }

    func fluidHoverItem<ID: Hashable>(_ id: ID, isEnabled: Bool = true, action: (() -> Void)? = nil) -> some View {
        modifier(FluidHoverItem(id: AnyHashable(id), isEnabled: isEnabled, action: action))
    }
}

/// Which item of the nearest group is highlighted, for items that change their own look with it.
struct FluidHoverActiveKey: EnvironmentKey {
    static let defaultValue: AnyHashable? = nil
}

extension EnvironmentValues {
    var fluidHoverActive: AnyHashable? {
        get { self[FluidHoverActiveKey.self] }
        set { self[FluidHoverActiveKey.self] = newValue }
    }
}

private struct FluidHoverFrames: PreferenceKey {
    static let defaultValue: [AnyHashable: CGRect] = [:]
    static func reduce(value: inout [AnyHashable: CGRect], nextValue: () -> [AnyHashable: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct FluidHoverActions: PreferenceKey {
    static let defaultValue: [AnyHashable: FluidAction] = [:]
    static func reduce(value: inout [AnyHashable: FluidAction], nextValue: () -> [AnyHashable: FluidAction]) {
        value.merge(nextValue()) { $1 }
    }
}

/// A closure that preferences can compare (always equal; the latest wins).
struct FluidAction: Equatable {
    let run: () -> Void
    static func == (lhs: FluidAction, rhs: FluidAction) -> Bool { true }
}

private struct FluidHoverSpaceKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

private extension EnvironmentValues {
    var fluidHoverSpace: String? {
        get { self[FluidHoverSpaceKey.self] }
        set { self[FluidHoverSpaceKey.self] = newValue }
    }
}

private struct FluidHoverItem: ViewModifier {
    let id: AnyHashable
    let isEnabled: Bool
    let action: (() -> Void)?
    @Environment(\.fluidHoverSpace) private var space

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { proxy in
                Color.clear.preference(key: FluidHoverFrames.self,
                                       value: isEnabled && space != nil ? [id: proxy.frame(in: .named(space!))] : [:])
            })
            .preference(key: FluidHoverActions.self, value: isEnabled ? action.map { [id: FluidAction(run: $0)] } ?? [:] : [:])
    }
}

private struct FluidHoverGroup: ViewModifier {
    let axis: Axis?
    let highlight: Color
    let radius: CGFloat
    let isEnabled: Bool

    @State private var space = "fluid-hover-\(UUID().uuidString)"
    @State private var frames: [AnyHashable: CGRect] = [:]
    @State private var actions: [AnyHashable: FluidAction] = [:]
    @State private var active: AnyHashable?
    @State private var shown: CGRect?

    func body(content: Content) -> some View {
        content
            .environment(\.fluidHoverSpace, space)
            .environment(\.fluidHoverActive, active)
            .background(alignment: .topLeading) {
                if let shown {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(highlight)
                        .frame(width: shown.width, height: shown.height)
                        .offset(x: shown.minX, y: shown.minY)
                        .transition(.asymmetric(insertion: .opacity.animation(Fluid.Motion.fade),
                                                removal: .opacity.animation(Fluid.Motion.fastExit)))
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: space)
            .onPreferenceChange(FluidHoverFrames.self) { frames = $0; refreshShown(animated: false) }
            .onPreferenceChange(FluidHoverActions.self) { actions = $0 }
            .onContinuousHover(coordinateSpace: .named(space)) { phase in
                guard isEnabled else { return }
                switch phase {
                case .active(let location):
                    let nearest = Self.nearest(to: location, in: frames, axis: axis)
                    if nearest != active {
                        let entering = active == nil
                        active = nearest
                        refreshShown(animated: !entering)
                    }
                case .ended:
                    active = nil
                    withAnimation(Fluid.Motion.fastExit) { shown = nil }
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded {
                // A click in a gap or the padding goes to the highlighted item; clicks on the item itself are
                // handled by the item, so this only acts when the item has registered an action.
                if let active, let action = actions[active] { action.run() }
            })
    }

    private func refreshShown(animated: Bool) {
        guard let active, let rect = frames[active] else {
            if active == nil, shown != nil { withAnimation(Fluid.Motion.fastExit) { shown = nil } }
            return
        }
        if shown == nil {
            // A fresh visit fades in where the pointer is, instead of sliding over from where it was last.
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { shown = rect }
        } else if animated {
            withAnimation(Fluid.Motion.fast) { shown = rect }
        } else {
            shown = rect
        }
    }

    /// The item the pointer is inside, or else the one whose center is nearest (along the axis, or straight-line).
    static func nearest(to point: CGPoint, in frames: [AnyHashable: CGRect], axis: Axis?) -> AnyHashable? {
        if let inside = frames.first(where: { $0.value.contains(point) }) { return inside.key }
        return frames.min { a, b in
            func distance(_ rect: CGRect) -> CGFloat {
                switch axis {
                case .vertical: return abs(rect.midY - point.y)
                case .horizontal: return abs(rect.midX - point.x)
                case nil: return hypot(rect.midX - point.x, rect.midY - point.y)
                }
            }
            return distance(a.value) < distance(b.value)
        }?.key
    }
}
