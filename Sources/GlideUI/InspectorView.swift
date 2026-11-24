import AVFoundation
import AppKit
import GlideCore
import SwiftUI
import UniformTypeIdentifiers

public enum InspectorTab: String, CaseIterable, Identifiable {
    case background, cursor, camera, zoom, clip, blur, audio, captions, export

    /// The panes with an icon. Clip opens by picking a clip on the timeline, and Export by its button.
    static let withIcons: [InspectorTab] = allCases.filter { $0 != .clip && $0 != .export }

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .background: return "Look"
        case .cursor: return "Cursor"
        case .camera: return "Camera"
        case .zoom: return "Zoom"
        case .clip: return "Clip"
        case .blur: return "Blur"
        case .audio: return "Audio"
        case .captions: return "Captions"
        case .export: return "Export"
        }
    }

    var icon: String {
        switch self {
        case .background: return "photo.on.rectangle"
        case .cursor: return "cursorarrow"
        case .camera: return "web.camera"
        case .zoom: return "plus.magnifyingglass"
        case .clip: return "scissors"
        case .blur: return "eye.slash"
        case .audio: return "speaker.wave.2"
        case .captions: return "captions.bubble"
        case .export: return "square.and.arrow.up"
        }
    }
}

/// The settings, as a floating panel on the window's right edge: the icons that choose a pane, and that pane under its title.
struct InspectorView: View {
    @ObservedObject var model: EditorModel
    @Binding var tab: InspectorTab

    static let panelWidth: CGFloat = 336

    var body: some View {
        panel
        .environment(\.fluidSurfaceLevel, 2)
        // Picking something on the timeline opens the pane that edits it.
        .onChange(of: model.selection) { _, selection in
            switch selection {
            case .zoom: tab = .zoom
            case .slice: tab = .clip
            case .mask: tab = .blur
            case .none: break
            }
        }
    }

    private var panel: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            PaneBar(tab: $tab)
                .padding(.horizontal, 12)
                .frame(height: 36)
            Text(tab.title)
                .font(Fluid.font(.title, .semibold, density: .regular))
                .foregroundStyle(Fluid.foreground)
                .padding(.horizontal, 16)
                .frame(height: 44, alignment: .center)
                .id(tab)
                .transition(.opacity.animation(Fluid.Motion.fast))
            Rectangle().fill(Fluid.border).frame(height: 1).padding(.horizontal, 16)

            FluidScrollArea {
                VStack(alignment: .leading, spacing: 0) {
                    switch tab {
                    case .background: BackgroundPane(model: model)
                    case .cursor: CursorPane(model: model)
                    case .camera: CameraPane(model: model)
                    case .zoom: ZoomPane(model: model)
                    case .clip: ClipPane(model: model)
                    case .blur: BlurPane(model: model)
                    case .audio: AudioPane(model: model)
                    case .captions: CaptionsPane(model: model)
                    case .export: ExportPane(model: model)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Each pane opens at its top, not wherever the last one was scrolled to.
            .id(tab)
        }
        .frame(width: Self.panelWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.panel, in: shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
        .clipShape(shape)
    }
}

/// The pane icons, spread across the panel. The chosen one sits on Fluid's selection fill, which springs from pane to pane;
/// the others light up under the pointer, and each names its pane in a tooltip under it.
private struct PaneBar: View {
    @Binding var tab: InspectorTab
    @State private var hovered: InspectorTab?
    @State private var settled = false

    private let tile: CGFloat = 28
    private var gap: CGFloat {
        let count = CGFloat(InspectorTab.withIcons.count)
        return (InspectorView.panelWidth - 24 - count * tile) / (count - 1)
    }

    var body: some View {
        HStack(spacing: gap) {
            ForEach(InspectorTab.withIcons) { pane in
                let chosen = pane == tab
                Button { tab = pane } label: {
                    Image(systemName: pane.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(chosen || hovered == pane ? Fluid.foreground : Fluid.mutedForeground)
                        .frame(width: tile, height: tile)
                        .background {
                            if hovered == pane && !chosen {
                                RoundedRectangle(cornerRadius: Fluid.Radius.item, style: .continuous).fill(Fluid.hover)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .onHover { inside in
                    if inside { hovered = pane } else if hovered == pane { hovered = nil }
                }
                .fluidTooltip(pane.title, side: .bottom)
                .accessibilityLabel(pane.title)
                .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
            }
        }
        .background(alignment: .leading) {
            // Clip and Export have no icon to sit under.
            if let index = InspectorTab.withIcons.firstIndex(of: tab) {
                RoundedRectangle(cornerRadius: Fluid.Radius.item, style: .continuous)
                    .fill(Fluid.active)
                    .frame(width: tile, height: tile)
                    .offset(x: CGFloat(index) * (tile + gap))
                    .animation(settled ? Fluid.Motion.moderate : nil, value: index)
            }
        }
        .animation(.easeOut(duration: 0.08), value: hovered)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { settled = true } }
    }
}

/// Segmented tabs over every case of an enum, sharing the width.
private func segments<Value: Hashable & CaseIterable>(_ selection: Binding<Value>, title: @escaping (Value) -> String) -> some View
    where Value.AllCases: RandomAccessCollection {
    FluidTabs(selection: selection, items: Value.allCases.map { FluidTabItem($0, title($0)) }, fill: true)
}

// MARK: Pictures to pick

/// A row of pictures to pick from, each showing what it does, with a short name under it.
private struct PictureChoices<Value: Hashable, Picture: View>: View {
    @Binding var selection: Value
    let choices: [(value: Value, name: String)]
    var columns: Int
    var height: CGFloat = 40
    @ViewBuilder let picture: (Value) -> Picture

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns), spacing: 6) {
            ForEach(choices, id: \.value) { choice in
                VStack(spacing: 2) {
                    SwatchRing(isSelected: selection == choice.value, height: height, help: nil, action: { selection = choice.value }) {
                        ZStack {
                            Fluid.surface4
                            picture(choice.value)
                        }
                    }
                    Text(choice.name)
                        .font(Fluid.font(.caption))
                        .foregroundStyle(selection == choice.value ? Fluid.foreground : Fluid.mutedForeground)
                        .lineLimit(1)
                }
            }
        }
    }
}

/// The screen in a small picture, for showing where things go around it.
private let miniScreen = Color(white: 0.42)
/// The camera or other highlighted part in a small picture.
private let miniHighlight = Color(fluidHex: 0xC4B5FD)

private struct AspectPicture: View {
    let aspect: AspectChoice

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
        switch aspect {
        case .auto:
            Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(Fluid.foreground)
        case .wide: shape.fill(miniScreen).frame(width: 30, height: 17)
        case .standard: shape.fill(miniScreen).frame(width: 26, height: 20)
        case .square: shape.fill(miniScreen).frame(width: 22, height: 22)
        case .portrait: shape.fill(miniScreen).frame(width: 19, height: 24)
        case .vertical: shape.fill(miniScreen).frame(width: 14, height: 25)
        }
    }
}

private struct DevicePicture: View {
    let frame: DeviceFrame

    var body: some View {
        switch frame {
        case .none:
            RoundedRectangle(cornerRadius: 2).fill(miniScreen).frame(width: 34, height: 22)
        case .browser:
            VStack(spacing: 0) {
                HStack(spacing: 1.5) {
                    ForEach(0..<3, id: \.self) { _ in Circle().fill(Color.white.opacity(0.75)).frame(width: 2.5, height: 2.5) }
                    Spacer()
                }
                .padding(.horizontal, 3)
                .frame(height: 6)
                .background(Color(white: 0.24))
                miniScreen
            }
            .frame(width: 36, height: 25)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        case .laptop:
            VStack(spacing: 0) {
                miniScreen.frame(width: 30, height: 20).padding(1.5).background(Color.black)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 2.5, topTrailingRadius: 2.5))
                RoundedRectangle(cornerRadius: 1).fill(Color(white: 0.7)).frame(width: 40, height: 2.5)
            }
        case .monitor:
            VStack(spacing: 0) {
                miniScreen.frame(width: 32, height: 19).padding(1.5).background(Color.black).clipShape(RoundedRectangle(cornerRadius: 2))
                Rectangle().fill(Color(white: 0.6)).frame(width: 5, height: 3)
                RoundedRectangle(cornerRadius: 1).fill(Color(white: 0.6)).frame(width: 16, height: 2)
            }
        }
    }
}

// MARK: Look

private struct GradientPreset: Identifiable {
    let name: String
    let top: UInt32
    let bottom: UInt32
    var id: String { name }

    static let all = [
        GradientPreset(name: "Dusk", top: 0x4776E6, bottom: 0x8E54E9),
        GradientPreset(name: "Sunrise", top: 0xFF9A8B, bottom: 0xFF6A88),
        GradientPreset(name: "Mint", top: 0x43E97B, bottom: 0x38B6A8),
        GradientPreset(name: "Ocean", top: 0x2193B0, bottom: 0x6DD5ED),
        GradientPreset(name: "Graphite", top: 0x232526, bottom: 0x4B4F52),
        GradientPreset(name: "Peach", top: 0xFFB88C, bottom: 0xDE6262),
        GradientPreset(name: "Aurora", top: 0x00C9FF, bottom: 0x7BE495),
        GradientPreset(name: "Berry", top: 0x8E2DE2, bottom: 0x4A00E0),
        GradientPreset(name: "Slate", top: 0x485563, bottom: 0x29323C),
        GradientPreset(name: "Sand", top: 0xE9D8C4, bottom: 0x8A7A6B),
        GradientPreset(name: "Rose", top: 0xF857A6, bottom: 0xFF5858),
        GradientPreset(name: "Night", top: 0x0F2027, bottom: 0x2C5364),
    ]
}

private let solidPresets: [UInt32] = [0xFFFFFF, 0xF3F4F6, 0xD1D5DB, 0x6B7280, 0x1F2937, 0x000000,
                                      0xFEE2E2, 0xFEF3C7, 0xD1FAE5, 0xDBEAFE, 0xEDE9FE, 0xFCE7F3]

/// A picture to pick, ringed like Fluid's color swatches: gray under the pointer, focus blue when chosen.
private struct SwatchRing<Content: View>: View {
    var isSelected: Bool
    var height: CGFloat = 30
    let help: String?
    let action: () -> Void
    @ViewBuilder var content: Content
    @State private var hovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Fluid.Radius.item, style: .continuous)
        Button(action: action) {
            content
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color(white: 0.5, opacity: 0.25), lineWidth: 1))
                .padding(3)
                .overlay {
                    if isSelected || hovered {
                        RoundedRectangle(cornerRadius: Fluid.Radius.item + 3, style: .continuous)
                            .strokeBorder(isSelected ? Fluid.focusRing : Color(white: 0.5, opacity: 0.4), lineWidth: 2)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.1), value: hovered)
        .fluidTooltip(help)
        .accessibilityLabel(help ?? "")
    }
}

private struct BackgroundPane: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        let style = model.project.settings.style
        InspectorSection(title: "Layout") {
            PictureChoices(selection: model.binding(\.settings.style.aspect, "aspect"),
                           choices: AspectChoice.allCases.map { ($0, $0.title) }, columns: 6, height: 32) { AspectPicture(aspect: $0) }
            SliderRow(title: "Padding", value: model.binding(\.settings.style.padding, "padding"), range: 0...0.25)
            if style.deviceFrame == .none && style.mockup == nil {
                SliderRow(title: "Corners", value: model.binding(\.settings.style.cornerRadius, "radius"), range: 0...0.05)
            }
        }

        InspectorSection(title: "Frame") {
            PictureChoices(selection: Binding(get: { style.mockup == nil ? style.deviceFrame : nil },
                                              set: { frame in
                                                  model.edit {
                                                      // A flat frame takes the place of a 3D device.
                                                      $0.settings.style.mockup = nil
                                                      $0.settings.style.deviceFrame = frame ?? .none
                                                  }
                                              }),
                           choices: DeviceFrame.allCases.map { (Optional($0), $0.title) }, columns: 4, height: 44) { frame in
                if let frame { DevicePicture(frame: frame) }
            }
        }

        InspectorSection(title: "Background") {
            BackgroundKindPicker(model: model)
            backgroundOptions(style.activeBackground)
        }

        InspectorSection(title: "Shadow",
                         isOn: Binding(get: { style.shadowOpacity > 0 },
                                       set: { on in model.edit { $0.settings.style.shadowOpacity = on ? 0.35 : 0 } })) {
            SliderRow(title: "Strength", value: model.binding(\.settings.style.shadowOpacity, "shadow-opacity"), range: 0...0.8)
            SliderRow(title: "Softness", value: model.binding(\.settings.style.shadowBlur, "shadow-blur"), range: 0.005...0.08)
            SliderRow(title: "Distance", value: model.binding(\.settings.style.shadowDistance, "shadow-distance"), range: 0...0.06)
            SliderRow(title: "Direction", value: model.binding(\.settings.style.shadowAngle, "shadow-angle"), range: 0...360,
                      display: { String(format: "%.0f°", $0) })
        }
    }

    @ViewBuilder
    private func backgroundOptions(_ background: GlideCore.BackgroundStyle) -> some View {
        switch background.kind {
        case .solid:
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 6), spacing: 2) {
                ForEach(solidPresets, id: \.self) { hex in
                    SwatchRing(isSelected: background.solid == RGB(hex: hex), height: 28, help: nil,
                               action: { model.edit { $0.settings.style.activeBackground.solid = RGB(hex: hex) } }) { Color(hex: hex) }
                }
            }
            FluidColorWell(color: model.colorBinding(\.settings.style.activeBackground.solid, "solid"))
        case .gradient:
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 6), spacing: 2) {
                ForEach(GradientPreset.all) { preset in
                    SwatchRing(isSelected: background.gradientTop == RGB(hex: preset.top) && background.gradientBottom == RGB(hex: preset.bottom),
                               height: 28, help: nil, action: {
                        model.edit {
                            $0.settings.style.activeBackground.gradientTop = RGB(hex: preset.top)
                            $0.settings.style.activeBackground.gradientBottom = RGB(hex: preset.bottom)
                        }
                    }) {
                        LinearGradient(colors: [Color(hex: preset.top), Color(hex: preset.bottom)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
            }
            HStack(spacing: 6) {
                FluidColorWell(color: model.colorBinding(\.settings.style.activeBackground.gradientTop, "gradient-top"))
                FluidColorWell(color: model.colorBinding(\.settings.style.activeBackground.gradientBottom, "gradient-bottom"))
                SliderRow(title: "", value: model.binding(\.settings.style.activeBackground.angle, "gradient-angle"), range: 0...360,
                          display: { String(format: "%.0f°", $0) })
            }
        case .wallpaper:
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 4), spacing: 2) {
                ForEach(Wallpapers.all) { wallpaper in
                    SwatchRing(isSelected: background.wallpaperID == wallpaper.id, height: 44, help: nil,
                               action: { model.edit { $0.settings.style.activeBackground.wallpaperID = wallpaper.id } }) {
                        WallpaperSwatch(id: wallpaper.id)
                    }
                }
            }
        case .image:
            SwatchRing(isSelected: false, height: 80, help: nil, action: chooseImage) {
                ZStack {
                    Fluid.surface4
                    if let file = background.imageFile,
                       let picture = NSImage(contentsOf: model.bundle.folder.appendingPathComponent(file)) {
                        Image(nsImage: picture).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "plus").font(.system(size: 16)).foregroundStyle(Fluid.mutedForeground)
                    }
                }
            }
            if background.imageFile != nil {
                SliderRow(title: "Blur", value: model.binding(\.settings.style.activeBackground.imageBlur, "image-blur"), range: 0...0.05)
            }
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a picture for the background"
        if panel.runModal() == .OK, let url = panel.url { model.setBackgroundImage(from: url) }
    }
}

/// The four kinds of background, each drawn as itself in the project's current colors, with no words.
private struct BackgroundKindPicker: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        let background = model.project.settings.style.activeBackground
        HStack(spacing: 2) {
            ForEach([BackgroundKind.solid, .gradient, .wallpaper, .image], id: \.self) { kind in
                SwatchRing(isSelected: background.kind == kind, height: 30, help: kind.title,
                           action: { model.edit { $0.settings.style.activeBackground.kind = kind } }) {
                    switch kind {
                    case .solid:
                        Color(background.solid)
                    case .gradient:
                        LinearGradient(colors: [Color(background.gradientTop), Color(background.gradientBottom)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    case .wallpaper:
                        WallpaperSwatch(id: background.wallpaperID)
                    case .image:
                        ZStack {
                            Fluid.surface4
                            Image(systemName: "photo").font(.system(size: 13)).foregroundStyle(Fluid.foreground)
                        }
                    }
                }
            }
        }
    }
}

private struct WallpaperSwatch: View {
    let id: String
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Theme.track
            if let image { Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill) }
        }
        .task(id: id) { image = Wallpapers.thumbnail(id: id, size: CGSize(width: 160, height: 110)) }
    }
}

// MARK: Cursor

/// The arrow of a cursor, its tip at the top left.
private struct ArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [(Double, Double)] = [(0, 0), (0, 16), (3.9, 12.4), (6.6, 18.6), (9.4, 17.4), (6.8, 11.5), (12, 11.5)]
        return Path { path in
            path.addLines(points.map { CGPoint(x: rect.minX + $0.0 / 12 * rect.width, y: rect.minY + $0.1 / 18.6 * rect.height) })
            path.closeSubpath()
        }
    }
}

private struct CursorPicture: View {
    let style: CursorStyle

    var body: some View {
        ZStack {
            // Halfway between light and dark, where both a black and a white cursor can be seen.
            Color(white: 0.6)
            switch style {
            case .dark:
                arrow(fill: .black, outline: .white)
            case .system:
                arrow(fill: .white, outline: .black)
            case .arrow:
                ArrowShape().fill(Color.black).frame(width: 15, height: 23)
            case .dot:
                Circle().fill(Color.black.opacity(0.75)).frame(width: 14, height: 14)
            case .ring:
                Circle().strokeBorder(Color.black, lineWidth: 2).frame(width: 20, height: 20)
            case .crosshair:
                Image(systemName: "plus").font(.system(size: 20, weight: .light)).foregroundStyle(Color.black)
            }
        }
    }

    private func arrow(fill: Color, outline: Color) -> some View {
        ArrowShape()
            .fill(fill)
            .overlay(ArrowShape().stroke(outline, style: StrokeStyle(lineWidth: 1.4, lineJoin: .round)))
            .frame(width: 13, height: 20)
    }
}

private struct CursorPane: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        InspectorSection(title: "Show cursor", isOn: model.binding(\.settings.style.showCursor, "show-cursor")) {
            PictureChoices(selection: model.binding(\.settings.style.cursorStyle, "cursor-style"),
                           choices: CursorStyle.allCases.map { ($0, $0.title) }, columns: 3, height: 46) { CursorPicture(style: $0) }
            SliderRow(title: "Size", value: model.binding(\.settings.style.cursorScale, "cursor-size"), range: 0.6...3,
                      display: { String(format: "%.1f×", $0) })
            ToggleRow(title: "Smooth movement", isOn: model.binding(\.settings.smoothCursor, "smooth-cursor"),
                      help: "Glides along a soft path instead of following every wobble of the mouse.")
            ToggleRow(title: "Lean while moving", isOn: model.binding(\.settings.style.cursorTilt, "cursor-tilt"),
                      help: "Tilts a little as it moves sideways.")
        }
        InspectorSection(title: "Click effect", isOn: model.binding(\.settings.style.clickEffect, "click-effect")) {
            FluidColorWell(color: model.colorBinding(\.settings.style.clickColor, "click-color"))
        }
    }
}

// MARK: Camera

/// A pane with nothing to set, because what it would set isn't in this recording.
private struct PaneEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 22)).foregroundStyle(Fluid.mutedForeground)
            Text(title).font(Fluid.font(.body, .semibold)).foregroundStyle(Fluid.foreground)
            Text(message).font(Fluid.font(.caption)).foregroundStyle(Fluid.mutedForeground).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 40)
    }
}

private struct CameraLayoutPicture: View {
    let layout: CameraLayout

    var body: some View {
        let screen = RoundedRectangle(cornerRadius: 1.5).fill(miniScreen)
        let camera = RoundedRectangle(cornerRadius: 1.5).fill(miniHighlight)
        Group {
            switch layout {
            case .bubble:
                screen.overlay(alignment: .bottomTrailing) { Circle().fill(miniHighlight).frame(width: 11, height: 11).padding(2) }
            case .splitRight:
                HStack(spacing: 1.5) { screen; camera.frame(width: 11) }
            case .splitLeft:
                HStack(spacing: 1.5) { camera.frame(width: 11); screen }
            case .splitTop:
                VStack(spacing: 1.5) { camera.frame(height: 8); screen }
            case .splitBottom:
                VStack(spacing: 1.5) { screen; camera.frame(height: 8) }
            case .cutout:
                screen.overlay(alignment: .bottomTrailing) {
                    Image(systemName: "person.fill").font(.system(size: 13)).foregroundStyle(miniHighlight).padding(.trailing, 2)
                }
            }
        }
        .frame(width: 38, height: 26)
    }
}

/// The four corners of a small screen, one to pick.
private struct CornerPicker: View {
    @Binding var corner: Corner

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Corner.allCases, id: \.self) { option in
                SwatchRing(isSelected: corner == option, height: 34, help: nil, action: { corner = option }) {
                    ZStack(alignment: alignment(option)) {
                        Fluid.surface4
                        RoundedRectangle(cornerRadius: 1.5).fill(miniScreen).frame(width: 34, height: 22)
                            .overlay(alignment: alignment(option)) { Circle().fill(miniHighlight).frame(width: 8, height: 8).padding(2) }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
    }

    private func alignment(_ corner: Corner) -> Alignment {
        switch corner {
        case .topLeft: return .topLeading
        case .topRight: return .topTrailing
        case .bottomLeft: return .bottomLeading
        case .bottomRight: return .bottomTrailing
        }
    }
}

private struct CameraPane: View {
    @ObservedObject var model: EditorModel

    private var layout: CameraLayout { model.project.settings.style.cameraLayout }

    var body: some View {
        if !model.hasWebcam {
            PaneEmptyState(icon: "web.camera", title: "No camera in this recording",
                           message: "Turn the camera on in Softcut's recording bar next time to add yourself to the video.")
        } else {
            InspectorSection(title: "Show camera", isOn: model.binding(\.settings.style.showWebcam, "show-webcam")) {
                PictureChoices(selection: model.binding(\.settings.style.cameraLayout, "camera-layout"),
                               choices: [(.bubble, "Bubble"), (.splitRight, "Right"), (.splitLeft, "Left"),
                                         (.splitTop, "Above"), (.splitBottom, "Below"), (.cutout, "Cut-out")],
                               columns: 3, height: 44) { CameraLayoutPicture(layout: $0) }
                if layout.isSplit {
                    SliderRow(title: "Size", value: model.binding(\.settings.style.splitRatio, "split-ratio"), range: 0.15...0.6)
                }
                if layout == .cutout {
                    SliderRow(title: "Size", value: model.binding(\.settings.style.cutoutSize, "cutout-size"), range: 0.25...0.9)
                }
                if layout == .bubble {
                    SliderRow(title: "Size", value: model.binding(\.settings.style.webcamSize, "webcam-size"), range: 0.1...0.45)
                    SliderRow(title: "Size when zoomed", value: model.binding(\.settings.style.webcamZoomedScale, "webcam-zoomed"), range: 0.4...1)
                    SliderRow(title: "From edge", value: model.binding(\.settings.style.webcamMargin, "webcam-margin"), range: 0...0.1)
                    PictureChoices(selection: model.binding(\.settings.style.webcamShape, "webcam-shape"),
                                   choices: [(.circle, "Circle"), (.roundedSquare, "Rounded")], columns: 2, height: 32) { shape in
                        Group {
                            if shape == .circle { Circle().fill(miniHighlight) } else { RoundedRectangle(cornerRadius: 5).fill(miniHighlight) }
                        }
                        .frame(width: 20, height: 20)
                    }
                }
                if layout == .bubble || layout == .cutout {
                    CornerPicker(corner: model.binding(\.settings.style.webcamCorner, "webcam-corner"))
                }
                ToggleRow(title: "Mirror", isOn: model.binding(\.settings.style.webcamMirror, "webcam-mirror"))
            }
        }
    }
}

// MARK: Zoom

/// A small screen with the part a zoom shows marked on it.
private struct ZoomKindPicture: View {
    let kind: ZoomPresentation

    var body: some View {
        RoundedRectangle(cornerRadius: 2).fill(miniScreen).frame(width: 40, height: 26).overlay {
            if kind == .camera {
                RoundedRectangle(cornerRadius: 1).stroke(miniHighlight, lineWidth: 1.5).frame(width: 20, height: 13)
            } else {
                Circle().fill(Color(white: 0.75)).overlay(Circle().stroke(miniHighlight, lineWidth: 1.5)).frame(width: 15, height: 15)
            }
        }
    }
}

private struct ZoomPane: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        InspectorSection(title: "Zoom in on clicks",
                         isOn: Binding(get: { model.anyZoomEnabled },
                                       set: { on in
                                           if on && model.allZooms.isEmpty { model.regenerateZooms() } else { model.setAllZooms(enabled: on) }
                                       })) {
            SliderRow(title: "Amount", value: Binding(get: { model.project.settings.zoomScale }, set: { model.setZoomAmount($0) }),
                      range: 1.2...4, display: { String(format: "%.1f×", $0) })
            ToggleRow(title: "Zoom in while typing",
                      isOn: Binding(get: { model.project.settings.zoomOnTyping },
                                    set: { on in
                                        model.edit { $0.settings.zoomOnTyping = on }
                                        model.regenerateZooms()
                                    }))
            ToggleRow(title: "Ease in and out", isOn: model.binding(\.settings.zoomEasing, "zoom-easing"))
            SliderRow(title: "Motion blur", value: model.binding(\.settings.style.motionBlur, "motion-blur"), range: 0...1)
            HStack(spacing: 6) {
                FluidButton("Add zoom", icon: "plus", variant: .tertiary) { model.addZoomAtPlayhead() }
                FluidButton("Choose again", icon: "wand.and.stars", variant: .ghost) { model.regenerateZooms() }
                    .fluidTooltip("Replaces every zoom with the ones Softcut chooses.")
            }
        }

        if let zoom = model.project.zoom(selectedZoomID) {
            InspectorSection(title: "This zoom",
                             isOn: Binding(get: { !zoom.isDisabled }, set: { v in model.updateZoom(zoom.id, key: "enabled") { $0.isDisabled = !v } })) {
                PictureChoices(selection: Binding(get: { zoom.presentation }, set: { v in model.updateZoom(zoom.id, key: "style") { $0.presentation = v } }),
                               choices: [(.camera, "Zoom"), (.loupe, "Magnifier")], columns: 2, height: 44) { ZoomKindPicture(kind: $0) }
                SliderRow(title: "Amount",
                          value: Binding(get: { zoom.scale }, set: { v in model.updateZoom(zoom.id, key: "scale") { $0.scale = v } }),
                          range: 1.2...5, display: { String(format: "%.1f×", $0) })
                if zoom.presentation == .loupe {
                    SliderRow(title: "Lens size", value: model.binding(\.settings.style.loupeSize, "loupe-size"), range: 0.08...0.3)
                } else {
                    FluidTabs(selection: Binding(get: { zoom.follow }, set: { v in model.updateZoom(zoom.id, key: "follow") { $0.follow = v } }),
                              items: [FluidTabItem(ZoomFollow.auto, "Follow cursor", icon: "cursorarrow.motionlines"),
                                      FluidTabItem(ZoomFollow.fixed, "Stay put", icon: "pin")],
                              fill: true)
                    ToggleRow(title: "Instant", isOn: Binding(get: { zoom.instant }, set: { v in model.updateZoom(zoom.id, key: "instant") { $0.instant = v } }))
                }
                FluidButton("Delete", icon: "trash", variant: .ghost) { model.deleteSelection() }
            }
        }
    }

    private var selectedZoomID: UUID? {
        if case .zoom(let id) = model.selection { return id }
        return nil
    }
}

// MARK: Clip

private struct ClipPane: View {
    @ObservedObject var model: EditorModel

    private static let speeds: [Double] = [0.5, 1, 1.5, 2, 3, 4, 8]

    var body: some View {
        InspectorSection(title: "Clip") {
            if let slice = selectedSlice {
                FluidTable(columns: [], rows: [["From", model.name(of: slice.sourceID)],
                                               ["Length", "\(timecode(slice.sourceDuration)) → \(timecode(slice.outputDuration))"]])
                    .padding(.horizontal, -10)
                Text("Speed").font(Fluid.font(.body)).foregroundStyle(Fluid.mutedForeground)
                FluidTabs(selection: Binding(get: { Self.speeds.min { abs($0 - slice.speed) < abs($1 - slice.speed) } ?? 1 },
                                             set: { model.setSpeed(slice.id, $0) }),
                          items: Self.speeds.map { FluidTabItem($0, $0 == $0.rounded() ? "\(Int($0))×" : String(format: "%.1f×", $0)) },
                          fill: true)
                ToggleRow(title: "Hide cursor", isOn: Binding(get: { slice.hideCursor }, set: { v in model.updateSlice(slice.id, key: "cursor") { $0.hideCursor = v } }))
                HStack(spacing: 8) {
                    FluidButton("Earlier", icon: "arrow.left", variant: .tertiary) { model.moveSelectedClip(by: -1) }
                        .disabled(!model.canMoveSelectedClipEarlier)
                    FluidButton("Later", trailingIcon: "arrow.right", variant: .tertiary) { model.moveSelectedClip(by: 1) }
                        .disabled(!model.canMoveSelectedClipLater)
                }
            } else {
                HelpText("Select a clip on the timeline to change its speed, move it, or cut it out.")
            }
        }

        InspectorSection(title: "Cut, copy and paste") {
            HStack(spacing: 8) {
                FluidButton("Cut", icon: "scissors", variant: .tertiary) { model.cutSelection() }
                    .disabled(selectedSlice == nil || model.project.slices.count < 2)
                FluidButton("Copy", icon: "doc.on.doc", variant: .tertiary) { model.copySelection() }
                    .disabled(selectedSlice == nil)
            }
            HStack(spacing: 8) {
                FluidButton("Paste after", icon: "doc.on.clipboard", variant: .tertiary) { model.paste() }
                    .disabled(!model.canPaste)
                FluidButton("Paste at end", icon: "arrow.down.to.line", variant: .tertiary) { model.pasteAtEnd() }
                    .disabled(!model.canPaste)
            }
            HelpText(model.canPaste ? "A clip is ready to paste." : "Cut or copy a clip to paste it somewhere else in the video, or at the end.")
        }

        InspectorSection(title: "Edit") {
            VStack(alignment: .leading, spacing: 2) {
                FluidButton("Split at playhead", icon: "scissors", variant: .ghost) { model.splitAtPlayhead() }
                FluidButton("Remove this clip", icon: "trash", variant: .ghost) { model.deleteSelection() }
                    .disabled(selectedSlice == nil || model.project.slices.count < 2)
                FluidButton("Restore everything that was cut", icon: "arrow.uturn.backward", variant: .ghost) { model.restoreCuts() }
                    .disabled(isWholeRecording)
            }
            .padding(.horizontal, -8)
            HelpText("Drag the ends of a clip on the timeline to trim it. Clips play one after another; cutting one closes the gap.")
        }
    }

    private var selectedSlice: TimeSegment? {
        if case .slice(let id) = model.selection { return model.project.slice(id) }
        return nil
    }

    /// True when each recording is one clip from start to end at normal speed, so there is nothing to restore.
    private var isWholeRecording: Bool {
        let sources = model.sourceOrder
        guard model.project.slices.count == sources.count else { return false }
        return model.project.slices.allSatisfy { clip in
            clip.sourceStart <= 0.01 && clip.sourceEnd >= model.duration(of: clip.sourceID) - 0.01 && clip.speed == 1
        }
    }
}

// MARK: Blur

/// A few lines of text, hidden the way a mask hides them.
private struct MaskKindPicture: View {
    let kind: MaskKind

    var body: some View {
        switch kind {
        case .blur:
            lines.blur(radius: 2.5)
        case .pixelate:
            let shades: [Double] = [0.8, 0.45, 0.65, 0.35, 0.55, 0.7, 0.4, 0.75, 0.5, 0.6, 0.35, 0.8, 0.55, 0.45, 0.7]
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<5, id: \.self) { column in Color(white: shades[row * 5 + column]).frame(width: 8, height: 8) }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
        case .fill:
            RoundedRectangle(cornerRadius: 2).fill(Color.black).frame(width: 40, height: 24)
        }
    }

    private var lines: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach([36.0, 24, 30], id: \.self) { width in Capsule().fill(Color.white).frame(width: width, height: 4) }
        }
    }
}

private struct BlurPane: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        if let mask = model.project.mask(selectedMaskID) {
            InspectorSection(title: "Hidden area",
                             isOn: Binding(get: { !mask.isDisabled }, set: { v in model.updateMask(mask.id, key: "enabled") { $0.isDisabled = !v } })) {
                PictureChoices(selection: Binding(get: { mask.kind }, set: { v in model.updateMask(mask.id, key: "kind") { $0.kind = v } }),
                               choices: MaskKind.allCases.map { ($0, $0.title) }, columns: 3, height: 44) { MaskKindPicture(kind: $0) }
                if mask.kind != .fill {
                    SliderRow(title: "Strength", value: Binding(get: { mask.strength }, set: { v in model.updateMask(mask.id, key: "strength") { $0.strength = v } }),
                              range: 0.05...1)
                }
                FluidButton("Delete", icon: "trash", variant: .ghost) { model.deleteSelection() }
            }
        } else {
            PaneEmptyState(icon: "rectangle.dashed", title: "Drag on the video",
                           message: "Draw over anything you want to hide. Drag its edges on the video to fit it, and its bar on the timeline to set how long it stays.")
        }
    }

    private var selectedMaskID: UUID? {
        if case .mask(let id) = model.selection { return id }
        return nil
    }
}

// MARK: Audio

/// Plays one of the built-in tracks for listening to before choosing it.
@MainActor
private final class MusicAudition: ObservableObject {
    @Published private(set) var playing: String?
    private var player: AVAudioPlayer?

    func toggle(_ track: BuiltInMusic.Track) async {
        let wasPlaying = playing == track.id
        stop()
        guard !wasPlaying else { return }
        playing = track.id
        guard let url = try? await Task.detached(priority: .userInitiated, operation: { try BuiltInMusic.url(for: track) }).value,
              playing == track.id, let next = try? AVAudioPlayer(contentsOf: url) else { return }
        next.volume = 0.6
        next.play()
        player = next
    }

    func stop() {
        player?.stop()
        player = nil
        playing = nil
    }
}

private enum SoundSource: Hashable { case library, upload, record }

private struct AudioPane: View {
    @ObservedObject var model: EditorModel
    @StateObject private var audition = MusicAudition()
    @State private var source = SoundSource.library

    var body: some View {
        let manifest = model.bundle.manifest
        let audio = model.project.audio
        let hasSound = manifest.hasMicrophone || manifest.hasSystemAudio

        if hasSound {
            InspectorSection(title: "Recorded sound",
                             isOn: Binding(get: { !(audio.muteMicrophone || !manifest.hasMicrophone) || !(audio.muteSystemAudio || !manifest.hasSystemAudio) },
                                           set: { model.setRecordedSoundMuted(!$0) })) {
                SliderRow(title: "Volume", value: model.binding(\.audio.volume, "volume"), range: 0...1.5)
                if manifest.hasMicrophone && manifest.hasSystemAudio {
                    ToggleRow(title: "Microphone", isOn: Binding(get: { !audio.muteMicrophone }, set: { v in model.edit(coalescing: "mute-mic") { $0.audio.muteMicrophone = !v } }))
                    ToggleRow(title: "System audio", isOn: Binding(get: { !audio.muteSystemAudio }, set: { v in model.edit(coalescing: "mute-system") { $0.audio.muteSystemAudio = !v } }))
                }
            }
        }

        InspectorSection(title: hasSound ? "Add sound" : "This recording has no sound. Add some") {
            FluidTabs(selection: $source,
                      items: [FluidTabItem(SoundSource.library, "Music", icon: "music.note"),
                              FluidTabItem(SoundSource.upload, "Upload", icon: "square.and.arrow.up"),
                              FluidTabItem(SoundSource.record, "Record", icon: "mic")],
                      fill: true)
            switch source {
            case .library: library(chosen: audio.music?.name)
            case .upload:
                FluidButton("Choose a sound file…", icon: "folder", variant: .tertiary) { chooseMusic() }
            case .record:
                FluidButton(model.isRecordingVoiceOver ? "Stop recording" : "Record from the playhead",
                            icon: model.isRecordingVoiceOver ? "stop.fill" : "mic.fill",
                            variant: model.isRecordingVoiceOver ? .primary : .secondary) {
                    if model.isRecordingVoiceOver { model.stopVoiceOver() } else { Task { await model.startVoiceOver() } }
                }
                .disabled(model.previewState != .ready)
                if model.isRecordingVoiceOver {
                    FluidThinkingIndicator(words: ["Recording", "Listening"], density: .compact).padding(.horizontal, -12)
                }
            }
        }
        .onDisappear { audition.stop() }

        if let music = audio.music {
            InspectorSection(title: music.name, isOn: Binding(get: { true }, set: { _ in model.removeMusic() })) {
                if !FileManager.default.fileExists(atPath: music.path) {
                    FluidBanner(status: .warning, title: "This file has moved", message: "No music plays until you choose it again.")
                }
                SliderRow(title: "Volume", value: Binding(get: { music.volume }, set: { value in model.updateMusic(key: "music-volume") { $0.volume = value } }),
                          range: 0...1)
                ToggleRow(title: "Repeat", isOn: Binding(get: { music.loops }, set: { value in model.updateMusic(key: "music-loop") { $0.loops = value } }))
            }
        }

        ForEach(Array(audio.voiceOvers.enumerated()), id: \.element.id) { index, voice in
            InspectorSection(title: "Recording \(index + 1)", isOn: Binding(get: { true }, set: { _ in model.removeVoiceOver(voice.id) })) {
                SliderRow(title: "Starts at", value: Binding(get: { voice.start }, set: { value in model.updateVoiceOver(voice.id, key: "voice-start-\(voice.id)") { $0.start = value } }),
                          range: 0...max(0.5, model.outputDuration - 0.3), display: { timecode($0) })
                SliderRow(title: "Volume", value: Binding(get: { voice.volume }, set: { value in model.updateVoiceOver(voice.id, key: "voice-volume-\(voice.id)") { $0.volume = value } }),
                          range: 0...1.5)
            }
        }

        InspectorSection(title: "Click sounds", isOn: model.binding(\.audio.clickSounds, "click-sounds")) {
            SliderRow(title: "Volume", value: model.binding(\.audio.clickVolume, "click-volume"), range: 0...1)
        }
    }

    private func library(chosen: String?) -> some View {
        VStack(spacing: 2) {
            ForEach(BuiltInMusic.tracks) { track in
                let isChosen = chosen == track.name
                HStack(spacing: 8) {
                    FluidIconButton(systemName: audition.playing == track.id ? "pause.fill" : "play.fill", help: "Listen") {
                        Task { await audition.toggle(track) }
                    }
                    Text(track.name).font(Fluid.font(.body)).foregroundStyle(Fluid.foreground)
                    Spacer()
                    if isChosen {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Fluid.focusRing)
                    }
                }
                .padding(.trailing, 8)
                .frame(height: 32)
                .background(isChosen ? Fluid.active : Color.clear, in: RoundedRectangle(cornerRadius: Fluid.Radius.item, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture { Task { await model.chooseBuiltInMusic(track) } }
            }
        }
    }

    private func chooseMusic() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a sound file for the video"
        if panel.runModal() == .OK, let url = panel.url { Task { await model.chooseMusic(from: url) } }
    }
}

// MARK: Captions

private enum CaptionSource: Hashable { case automatic, file }

private struct CaptionsPane: View {
    @ObservedObject var model: EditorModel
    @State private var languages: [Locale] = []
    @State private var source = CaptionSource.automatic
    @AppStorage("captionLanguage") private var language = Locale.current.identifier

    var body: some View {
        let captions = model.allCaptions
        InspectorSection(title: captions.isEmpty ? "Add captions" : "Replace captions") {
            FluidTabs(selection: $source,
                      items: [FluidTabItem(CaptionSource.automatic, "Auto-generate", icon: "wand.and.stars"),
                              FluidTabItem(CaptionSource.file, "From a file", icon: "doc.text")],
                      fill: true)
            if source == .automatic {
                if !languages.isEmpty {
                    FluidCombobox(selection: $language, options: languages.map {
                        FluidOption($0.identifier, $0.localizedString(forIdentifier: $0.identifier) ?? $0.identifier)
                    }, icon: "globe")
                }
                if model.isTranscribing {
                    FluidThinkingIndicator(words: ["Listening", "Transcribing", "Timing the lines"], density: .compact)
                        .padding(.horizontal, -12)
                } else {
                    FluidButton("Generate", icon: "wand.and.stars", variant: .accent) {
                        Task { await model.generateCaptions(language: language) }
                    }
                }
            } else {
                FluidButton("Choose .srt or .vtt…", icon: "folder", variant: .tertiary) { chooseFile() }
            }
        }

        if !captions.isEmpty {
            InspectorSection(title: "Show captions", isOn: model.binding(\.settings.style.showCaptions, "show-captions")) {
                SliderRow(title: "Text size", value: model.binding(\.settings.style.captionSize, "caption-size"), range: 0.016...0.05,
                          display: { String(format: "%.0f%%", ($0 - 0.016) / 0.034 * 100) })
                PictureChoices(selection: model.binding(\.settings.style.captionPosition, "caption-position"),
                               choices: CaptionPosition.allCases.map { ($0, $0.title) }, columns: 2, height: 40) { position in
                    RoundedRectangle(cornerRadius: 2).fill(miniScreen).frame(width: 40, height: 26)
                        .overlay(alignment: position == .top ? .top : .bottom) {
                            Capsule().fill(Color.white).frame(width: 24, height: 3).padding(3)
                        }
                }
                ToggleRow(title: "Dark plate", isOn: model.binding(\.settings.style.captionBackground, "caption-plate"))
                ToggleRow(title: "Bold", isOn: model.binding(\.settings.style.captionBold, "caption-bold"))
                FluidColorWell(color: model.colorBinding(\.settings.style.captionColor, "caption-color"))
            }

            InspectorSection(title: "Lines") {
                LazyVStack(spacing: 6) {
                    ForEach(captions, id: \.line.id) { row in
                        HStack(alignment: .top, spacing: 4) {
                            if let start = row.outputStart {
                                FluidButton(timecode(start), variant: .ghost) { model.seek(toOutput: start) }
                                    .monospacedDigit()
                            } else {
                                FluidBadge(text: "Cut", color: .amber, dot: true).padding(.top, 4)
                            }
                            FluidInputField(placeholder: "Caption",
                                            text: Binding(get: { row.line.text },
                                                          set: { value in model.updateCaption(row.line.id, key: "caption-text-\(row.line.id)") { $0.text = value } }),
                                            multiline: true)
                            FluidIconButton(systemName: "trash", help: "Remove this line") { model.removeCaption(row.line.id) }
                        }
                        .opacity(row.outputStart == nil ? 0.5 : 1)
                    }
                }
                HStack(spacing: 6) {
                    FluidButton("Add line", icon: "plus", variant: .tertiary) { model.addCaptionAtPlayhead() }
                    FluidButton("Save .srt…", icon: "square.and.arrow.down", variant: .ghost) { saveSubtitles() }
                    Spacer()
                    FluidButton("Clear", variant: .ghost) { model.removeAllCaptions() }
                }
            }
        }

        Color.clear.frame(height: 0)
            .onAppear {
                if languages.isEmpty { languages = Transcriber.onDeviceLocales() }
                // The saved choice may be a language this Mac cannot recognize on its own; use the closest one that it can.
                if !languages.contains(where: { $0.identifier == language }) {
                    let wanted = Locale(identifier: language).language.languageCode
                    language = (languages.first { $0.language.languageCode == wanted }
                                ?? languages.first { $0.identifier == "en_US" } ?? languages.first)?.identifier ?? language
                }
            }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["srt", "vtt"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.message = "Choose a captions file"
        if panel.runModal() == .OK, let url = panel.url { model.importCaptions(from: url) }
    }

    private func saveSubtitles() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText]
        panel.nameFieldStringValue = "\(model.title).srt"
        if panel.runModal() == .OK, let url = panel.url { model.exportSubtitles(to: url) }
    }
}

// MARK: Export

private struct ExportPane: View {
    @ObservedObject var model: EditorModel

    private static let widths: [(String, Int)] = [("720p", 1280), ("1080p", 1920), ("1440p", 2560), ("4K", 3840)]

    var body: some View {
        let style = model.project.settings.style
        let size = OutputGeometry.size(for: model.bundle, style: style, hasWebcam: model.hasWebcam)

        InspectorSection(title: "Format") {
            FluidOptionCards(selection: $model.exportFormat, choices: [
                FluidChoice(ExportFormat.video, "Video", subtitle: "MP4, sharp and small, plays anywhere", icon: "film", badge: "play.fill"),
                FluidChoice(ExportFormat.gif, "Animated GIF", subtitle: "Loops in docs, chats and pull requests", icon: "photo.stack", badge: "repeat"),
            ])
        }

        if model.exportFormat == .video {
            InspectorSection(title: "Resolution") {
                FluidRadioGroup(selection: model.binding(\.settings.style.maxOutputWidth, "export-width"),
                                options: Self.widths.map { FluidOption($0.1, $0.0) },
                                details: Dictionary(uniqueKeysWithValues: Self.widths.map { name, width in
                                    (width, "\(width) × \(Int((Double(width) * size.height / max(size.width, 1)).rounded()))")
                                }))
                    .padding(.horizontal, -10)
            }
            InspectorSection(title: "Video") {
                FluidTabs(selection: model.binding(\.settings.style.fps, "export-fps"),
                          items: [FluidTabItem(30, "30 fps"), FluidTabItem(60, "60 fps")], fill: true)
                SettingRow(title: "Codec") {
                    FluidSelect(selection: $model.exportCodec, options: ExportCodec.allCases.map { FluidOption($0, $0.title) })
                }
                FluidTable(columns: [], rows: [["Size", "\(Int(size.width)) × \(Int(size.height))"],
                                               ["Frame rate", "\(style.fps) fps"],
                                               ["Length", timecode(model.outputDuration, tenths: false)]])
                    .padding(.horizontal, -10)
            }
        } else {
            InspectorSection(title: "GIF") {
                FluidTabs(selection: $model.gifWidth, items: [480, 640, 720, 960].map { FluidTabItem($0, "\($0) px") }, fill: true)
                FluidTabs(selection: $model.gifFPS, items: [10, 15, 20].map { FluidTabItem($0, "\($0) fps") }, fill: true)
                let frames = Int(model.outputDuration * Double(model.gifFPS))
                FluidTable(columns: [], rows: [["Size", "\(model.gifWidth) × \(Int(Double(model.gifWidth) * size.height / size.width))"],
                                               ["Frames", "\(frames)"]])
                    .padding(.horizontal, -10)
                if model.outputDuration > 30 {
                    FluidBanner(status: .warning, title: "This GIF will be very large",
                                message: "GIFs get very large past about 30 seconds. Trim the video first, or export a video instead.")
                }
            }
        }

        InspectorSection(title: "Export") {
            switch model.exportState {
            case .idle:
                FluidButton("Export \(model.exportFormat == .video ? "video" : "GIF")…", icon: "square.and.arrow.up", variant: .primary, size: .regular) {
                    chooseDestination()
                }
                .disabled(model.previewState != .ready)
            case .running(let fraction):
                HStack {
                    FluidShimmerText(text: "Rendering…", font: Fluid.font(.body))
                    Spacer()
                    Text(String(format: "%.0f%%", fraction * 100)).font(Fluid.font(.body, monospacedDigits: true)).foregroundStyle(Fluid.mutedForeground)
                }
                FluidProgressBar(fraction: fraction)
            case .finished(let url):
                FluidBanner(status: .success, title: "Saved", message: url.lastPathComponent, highContrast: true,
                            onDismiss: { model.dismissExportResult() }) {
                    FluidButton("Show in Finder", variant: .secondary) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
                FluidInputCopy(value: url.path(percentEncoded: false))
            case .failed(let message):
                FluidBanner(status: .error, title: "Export failed", message: message, highContrast: true) {
                    FluidButton("Try again", variant: .secondary) { model.dismissExportResult() }
                }
            }
        }
    }

    private func chooseDestination() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [model.exportFormat == .video ? .mpeg4Movie : .gif]
        panel.nameFieldStringValue = model.title + "." + model.exportFormat.fileExtension
        panel.directoryURL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
        if panel.runModal() == .OK, let url = panel.url { model.export(to: url) }
    }
}

extension Color {
    init(_ rgb: RGB) { self.init(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b) }

    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}
