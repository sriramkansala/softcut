import AVFoundation
import AppKit
import GlideCore
import SwiftUI

/// Shows what a player draws, fitted inside the available space, without any built-in controls.
struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer
    /// Fills the frame instead of fitting inside it, for a frame that changes shape: while it morphs there are no empty bars.
    var fillsFrame = false

    func makeNSView(context: Context) -> PlayerLayerView { PlayerLayerView() }

    func updateNSView(_ view: PlayerLayerView, context: Context) {
        view.gravity = fillsFrame ? .resizeAspectFill : .resizeAspect
        view.show(player)
    }
}

/// Draws a player. A new player's picture appears under the one showing, which only leaves once there is a frame to
/// replace it, so a preview that was rebuilt never blinks.
final class PlayerLayerView: NSView {
    private var shown: AVPlayerLayer?
    private var arriving: AVPlayerLayer?
    private var arrival: NSKeyValueObservation?

    var gravity = AVLayerVideoGravity.resizeAspect {
        didSet {
            shown?.videoGravity = gravity
            arriving?.videoGravity = gravity
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(_ player: AVPlayer) {
        if arriving?.player === player || (arriving == nil && shown?.player === player) { return }
        arriving?.removeFromSuperlayer()
        arriving = nil
        arrival = nil
        if shown?.player === player { return }

        let next = AVPlayerLayer(player: player)
        next.videoGravity = gravity
        next.backgroundColor = NSColor.clear.cgColor
        next.frame = bounds
        guard let shown else {
            layer?.addSublayer(next)
            self.shown = next
            return
        }
        layer?.insertSublayer(next, below: shown)
        arriving = next
        arrival = next.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            guard layer.isReadyForDisplay else { return }
            DispatchQueue.main.async { self?.land(layer) }
        }
    }

    private func land(_ layer: AVPlayerLayer) {
        guard layer === arriving else { return }
        shown?.removeFromSuperlayer()
        shown = layer
        arriving = nil
        arrival = nil
    }

    override func layout() {
        super.layout()
        // Layers added by hand animate every change by default, which would leave the picture trailing behind its frame.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shown?.frame = bounds
        arriving?.frame = bounds
        CATransaction.commit()
    }
}

/// The picture panel: the live preview (or a still, when drawing the editor to an image) with rounded corners. Clicking
/// the picture or pressing Space plays and pauses.
struct PreviewArea: View {
    @ObservedObject var model: EditorModel
    var stillImage: CGImage?
    /// The settings pane that is open, which decides what can be placed on the video.
    var tab = InspectorTab.background
    @State private var cropping = false

    /// Playing always shows the finished picture.
    private var stageMode: StageMode? {
        guard stillImage == nil, !model.isPlaying, model.previewState == .ready else { return nil }
        if cropping { return .crop }
        switch (tab, model.selection) {
        case (.blur, _):
            return .masks
        case (.zoom, .zoom(let id)):
            return model.project.zoom(id)?.presentation == .camera ? .zoom(id) : nil
        default:
            return nil
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let size = OutputGeometry.size(for: model.bundle, style: model.project.settings.style, hasWebcam: model.hasWebcam)
        let aspect = size.width / max(1, size.height)
        ZStack {
            Group {
                if let stillImage {
                    Image(decorative: stillImage, scale: 1).resizable()
                } else {
                    PlayerSurface(player: model.player, fillsFrame: true)
                }
            }
            .aspectRatio(aspect, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { model.togglePlay() }
            // The frame morphs to a new shape.
            .animation(.spring(duration: 0.3, bounce: 0), value: aspect)

            switch stillImage == nil ? model.previewState : .ready {
            case .loading:
                FluidThinkingIndicator(words: ["Preparing preview", "Loading frames"])
                    .padding(.horizontal, 4)
                    .fluidSurface(4, radius: Fluid.Radius.container)
            case .failed(let message):
                FluidBanner(status: .error, title: "The preview could not be made", message: message, highContrast: true)
                    .frame(maxWidth: 380)
                    .background(Fluid.surface2, in: RoundedRectangle(cornerRadius: Fluid.Radius.container, style: .continuous))
            case .ready:
                EmptyView()
            }

            if let stageMode {
                PreviewStage(model: model, mode: stageMode) { cropping = false }
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: stageMode)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: tab) { _, _ in cropping = false }
        .overlay(alignment: .topTrailing) {
            if stageMode == nil && stillImage == nil && !model.isPlaying {
                FluidIconButton(systemName: "crop", help: "Crop the video") { cropping = true }
                    .fluidSurface(4, radius: Fluid.Radius.item)
                    .padding(-6)
            }
        }
        .background {
            Button("") { model.togglePlay() }
                .keyboardShortcut(.space, modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .padding(14)
        .background(Theme.panel, in: shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
        .clipShape(shape)
    }
}

/// The big round play button of the finished video's window (Space plays and pauses).
struct RoundPlayButton: View {
    let isPlaying: Bool
    var size: CGFloat = 48
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: size / 3, weight: .semibold))
                .foregroundStyle(Fluid.foreground)
                .offset(x: isPlaying ? 0 : 1.5)
                .frame(width: size, height: size)
                .background(Circle().fill(hovered ? Fluid.surface4 : Fluid.surface3))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    .mask(Rectangle().frame(height: 2).frame(maxHeight: .infinity, alignment: .top)))
                .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.space, modifiers: [])
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.08), value: hovered)
        .fluidTooltip(isPlaying ? "Pause (Space)" : "Play (Space)")
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }
}
