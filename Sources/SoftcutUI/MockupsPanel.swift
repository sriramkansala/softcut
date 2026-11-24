import AppKit
import SoftcutCore
import SwiftUI

/// The Mockups tab: the 3D devices the video can be shown on, and how each one arrives.
struct MockupsPanel: View {
    @ObservedObject var model: EditorModel
    @State private var family: MockupFamily

    private let library = MockupLibrary.shared

    init(model: EditorModel) {
        self.model = model
        let current = model.project.settings.style.mockup.flatMap { MockupLibrary.shared.device(id: $0.deviceID) }
        _family = State(initialValue: current?.family ?? .macbook)
    }

    private var choice: MockupChoice? { model.project.settings.style.mockup }
    private var chosenDevice: MockupDevice? { choice.flatMap { library.device(id: $0.deviceID) } }

    var body: some View {
        FluidScrollArea {
            VStack(alignment: .leading, spacing: 14) {
                FluidTabs(selection: $family, items: MockupFamily.allCases.map {
                    FluidTabItem($0, $0.title, icon: $0 == .macbook ? "laptopcomputer" : "iphone")
                }, style: .subtle, fill: true)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 12) {
                    ForEach(library.entries(in: family)) { entry in
                        DeviceTile(entry: entry, isChosen: choice?.deviceID == entry.id) { put(in: entry) }
                    }
                }

                if let device = chosenDevice, let choice {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(device.family == family ? "How it arrives" : "It's on the \(device.name)")
                                .font(Fluid.font(.caption, .semibold))
                                .foregroundStyle(Fluid.mutedForeground)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            FluidButton("Remove", icon: "xmark", variant: .ghost) { model.setMockup(nil) }
                                .fluidTooltip("Take the video out of the device")
                        }
                        if device.family == family {
                            FluidOptionCards(selection: Binding(get: { choice.motionID },
                                                                set: { model.setMockup(MockupChoice(deviceID: device.id, motionID: $0)) }),
                                             choices: device.motions.map {
                                FluidChoice($0.id, $0.title, subtitle: $0.subtitle, icon: Self.icon(forMotion: $0.id))
                            })
                        }
                    }
                } else {
                    HelpText("Pick a device to show this recording on its screen, then choose how it arrives.")
                }
            }
            .padding(12)
        }
    }

    /// Choosing another device keeps the motion when the new one has it too.
    private func put(in entry: MockupLibrary.Entry) {
        guard let device = library.device(id: entry.id) else {
            model.notice = "Softcut could not load \(entry.name)."
            return
        }
        let motion = choice.flatMap { device.motion(id: $0.motionID) } ?? device.defaultMotion
        guard let motion else { return }
        model.setMockup(MockupChoice(deviceID: device.id, motionID: motion.id))
    }

    private static func icon(forMotion id: String) -> String {
        switch id {
        case "open-from-above": return "arrow.down"
        case "slide-in-open", "slide-in": return "arrow.left"
        case "rise": return "arrow.up"
        case "hero-reveal": return "sparkles"
        case "whip-turn", "spin-in": return "rotate.3d"
        case "slow-orbit": return "arrow.trianglehead.2.clockwise.rotate.90"
        case "tilt-up": return "angle"
        case "idle": return "wind"
        default: return "sparkles"
        }
    }
}

/// A device as its picture, with its name and finish underneath. The chosen one wears the purple ring.
private struct DeviceTile: View {
    let entry: MockupLibrary.Entry
    let isChosen: Bool
    let action: () -> Void

    @State private var hovered = false

    /// The pictures are small and the same few are drawn again and again.
    @MainActor private static var pictures: [String: NSImage] = [:]

    private var picture: NSImage? {
        if let picture = Self.pictures[entry.id] { return picture }
        let picture = MockupLibrary.shared.thumbnailURL(id: entry.id).flatMap { NSImage(contentsOf: $0) }
        Self.pictures[entry.id] = picture
        return picture
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(alignment: .leading, spacing: 6) {
            Color.white.opacity(hovered ? 0.07 : 0.04)
                .aspectRatio(3.0 / 2, contentMode: .fit)
                .overlay {
                    if let picture {
                        Image(nsImage: picture).resizable().aspectRatio(contentMode: .fit).padding(5)
                    } else {
                        Image(systemName: entry.family == .macbook ? "laptopcomputer" : "iphone").foregroundStyle(Fluid.mutedForeground)
                    }
                }
                .clipShape(shape)
                .overlay {
                    if isChosen {
                        shape.strokeBorder(Brand.base, lineWidth: 1.5).shadow(color: Brand.base.opacity(0.55), radius: 6)
                    } else {
                        shape.strokeBorder(Color.white.opacity(hovered ? 0.18 : 0.08), lineWidth: 1)
                    }
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.system(size: 11, weight: isChosen ? .semibold : .regular))
                    .foregroundStyle(hovered || isChosen ? Fluid.foreground : Fluid.mutedForeground)
                Text(entry.finish).font(.system(size: 10.5)).foregroundStyle(Fluid.mutedForeground.opacity(0.8))
            }
            .lineLimit(1)
            .padding(.leading, 2)
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture(perform: action)
        .animation(.easeOut(duration: 0.08), value: hovered)
        .animation(Fluid.Motion.moderate, value: isChosen)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.name), \(entry.finish)")
        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { action() }
    }
}
