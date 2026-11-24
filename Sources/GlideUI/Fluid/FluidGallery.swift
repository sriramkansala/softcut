import AppKit
import SwiftUI

/// Every Fluid component on one page, for checking them side by side (`glide-cli fluid-gallery OUT.png`).
struct FluidGallery: View {
    @State private var on = true
    @State private var off = false
    @State private var amount = 0.42
    @State private var angle = 135.0
    @State private var playhead = 12.0
    @State private var aspect = "16:9"
    @State private var tab = "look"
    @State private var subtle = "cursor"
    @State private var choice = "bubble"
    @State private var resolution = 1920
    @State private var mic = true
    @State private var system = true
    @State private var clicks = false
    @State private var open = true
    @State private var name = "Product demo"
    @State private var empty = ""
    @State private var color = Color(fluidHex: 0x6B97FF)
    @State private var dot = 1
    @State private var language = "en_US"
    @State private var sidebar = "all"

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 18) {
                heading("Button")
                HStack(spacing: 8) {
                    FluidButton("Save video", icon: "square.and.arrow.down", variant: .primary, size: .regular) {}
                    FluidButton("Edit", icon: "slider.horizontal.3", variant: .secondary, size: .regular) {}
                    FluidButton("Show in Finder", variant: .tertiary, size: .regular) {}
                    FluidButton("Cancel", variant: .ghost, size: .regular) {}
                }
                HStack(spacing: 8) {
                    FluidButton("Compact", variant: .primary) {}
                    FluidButton("Secondary", variant: .secondary) {}
                    FluidButton("Tertiary", variant: .tertiary) {}
                    FluidButton("Loading", variant: .primary, loading: true) {}
                    FluidIconButton(systemName: "arrow.uturn.backward", help: "Undo") {}
                    FluidIconButton(systemName: "ellipsis", variant: .tertiary, help: "More") {}
                }
                heading("Switch")
                HStack(spacing: 16) {
                    FluidSwitch(title: "Smooth movement", isOn: $on)
                    FluidSwitch(title: "Easing", isOn: $off)
                    FluidSwitchTrack(isOn: $on, density: .regular)
                }
                heading("Slider")
                FluidSlider(title: "Padding", value: $amount).frame(width: 300)
                FluidSlider(title: "Angle", value: $angle, range: 0...360, format: { String(format: "%.0f°", $0) }).frame(width: 300)
                FluidTrackSlider(value: $playhead, range: 0...60).frame(width: 300)
                heading("Tabs")
                FluidTabs(selection: $aspect, items: ["16:9", "4:3", "1:1", "9:16"].map { FluidTabItem($0, $0) }, fill: true)
                    .frame(width: 300)
                FluidTabs(selection: $tab, items: [FluidTabItem("look", "Look", icon: "photo"), FluidTabItem("cursor", "Cursor", icon: "cursorarrow"),
                                                   FluidTabItem("zoom", "Zoom", icon: "plus.magnifyingglass")], style: .subtle)
                FluidTabs(selection: $subtle, items: [FluidTabItem("look", "Look", icon: "photo"), FluidTabItem("cursor", "Cursor", icon: "cursorarrow"),
                                                      FluidTabItem("zoom", "Zoom", icon: "plus.magnifyingglass"), FluidTabItem("audio", "Audio", icon: "speaker.wave.2")],
                          style: .subtleIcons)
                heading("Select · Dropdown · Combobox")
                HStack(spacing: 8) {
                    FluidSelect(selection: $choice, options: [FluidOption("bubble", "Bubble"), FluidOption("split", "Side by side")])
                    FluidDropdown(rows: { [.item("Rename", icon: "pencil") {}, .separator(), .item("Delete", icon: "trash", destructive: true) {}] }) { open in
                        HStack(spacing: 4) { Text("Primary"); Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)) }
                            .font(Fluid.font(.body)).padding(.horizontal, 10).frame(height: 28)
                            .foregroundStyle(open ? Fluid.foreground : Fluid.mutedForeground)
                    }
                    FluidCombobox(selection: $language, options: [FluidOption("en_US", "English (US)"), FluidOption("fr_FR", "French")])
                        .frame(width: 160)
                }
                heading("Badge")
                HStack(spacing: 6) {
                    FluidBadge(text: "2.0×")
                    FluidBadge(text: "Edited", color: .blue)
                    FluidBadge(text: "Webcam", color: .green)
                    FluidBadge(text: "Cut out", color: .amber, dot: true)
                    FluidBadge(text: "Recording", color: .red, dot: true, density: .regular)
                }
                heading("Carousel dots")
                FluidCarouselDots(count: 4, index: $dot, progress: 0.6)
            }
            .frame(width: 440, alignment: .leading)

            VStack(alignment: .leading, spacing: 18) {
                heading("Banner")
                FluidBanner(status: .warning, title: "This file has moved", message: "No music plays until you choose it again.",
                            onDismiss: {}) {
                    FluidButton("Choose again", variant: .secondary) {}
                }
                FluidBanner(status: .success, title: "Saved to Movies", highContrast: true, onDismiss: {})
                FluidBanner(status: .info, title: "Recognition happens on this Mac")
                heading("Checkbox group · Radio group")
                HStack(alignment: .top, spacing: 12) {
                    FluidCheckboxGroup(items: [FluidCheckItem(id: "mic", title: "Microphone", isOn: $mic),
                                               FluidCheckItem(id: "sys", title: "System audio", isOn: $system),
                                               FluidCheckItem(id: "clk", title: "Click sounds", isOn: $clicks)])
                        .frame(width: 200)
                    FluidRadioGroup(selection: $resolution, options: [FluidOption(1280, "720p"), FluidOption(1920, "1080p"), FluidOption(3840, "4K")],
                                    details: [1280: "1280 × 720", 1920: "1920 × 1080", 3840: "3840 × 2160"])
                        .frame(width: 220)
                }
                heading("Accordion")
                FluidAccordionItem(title: "Shadow", isOpen: $open) {
                    Text("Strength, softness, distance and direction of the shadow under the video.")
                        .font(Fluid.font(.body)).foregroundStyle(Fluid.mutedForeground)
                }
                .frame(width: 420)
                heading("Input · Copy · Color")
                HStack(alignment: .bottom, spacing: 12) {
                    FluidInputField(label: "Name", placeholder: "Untitled", text: $name, icon: "textformat").frame(width: 200)
                    FluidInputField(label: "Caption", placeholder: "Type a line", text: $empty).frame(width: 200)
                }
                FluidInputCopy(label: "Saved to", value: "~/Movies/Glide/Exports/Product demo.mp4").frame(width: 420)
                FluidColorWell(label: "Text", color: $color)
                heading("Table")
                FluidTable(columns: ["", "Value"], rows: [["Size", "1920 × 1080"], ["Frame rate", "60 fps"], ["Length", "1:12"]])
                    .frame(width: 300)
                heading("Card list")
                FluidCardList(items: [GalleryRow(id: 1, title: "0:04.2", detail: "Zoom · 2.0×"), GalleryRow(id: 2, title: "0:11.8", detail: "Zoom · 2.4×")],
                              selection: 1, onSelect: { _ in }) { row, selected, _ in
                    FluidCardRow(title: row.title, detail: row.detail, icon: "plus.magnifyingglass", isSelected: selected) {
                        FluidBadge(text: "2.0×")
                    }
                }
                .frame(width: 420)
            }
            .frame(width: 440, alignment: .leading)

            VStack(alignment: .leading, spacing: 18) {
                heading("Thinking indicator · steps")
                FluidThinkingIndicator(words: ["Finding clicks", "Planning zooms"])
                FluidThinkingSteps(title: "Making your video", steps: [
                    FluidStep(id: "a", title: "Found 6 clicks", detail: "3 zooms planned", icon: "cursorarrow.click"),
                    FluidStep(id: "b", title: "Smoothing the cursor", icon: "scribble", status: .active),
                    FluidStep(id: "c", title: "Rendering", status: .pending),
                ])
                .frame(width: 320)
                heading("Color picker")
                FluidColorPicker(color: $color, showsAlpha: true, swatches: FluidColorWell.defaultSwatches)
                    .fluidSurface(3, radius: Fluid.Radius.container, shadow: 1)
                heading("Sidebar")
                FluidSidebarMenu(sections: [FluidSidebarSection(title: "Recordings", items: [
                    FluidSidebarItem(id: "all", title: "All recordings", icon: "film.stack", badge: "12"),
                    FluidSidebarItem(id: "edited", title: "Edited", icon: "slider.horizontal.3", badge: "4"),
                ])], selection: $sidebar)
                .frame(width: 240)
                heading("Shortcut caps · Tooltip")
                HStack(spacing: 12) {
                    FluidShortcutCaps(keys: "⌘K")
                    FluidTooltipBubble(text: "Undo (⌘Z)")
                }
            }
            .frame(width: 320, alignment: .leading)
        }
        .padding(28)
        .background(Fluid.background)
        .environment(\.colorScheme, .dark)
    }

    private func heading(_ text: String) -> some View {
        Text(text.uppercased()).font(Fluid.font(.micro, .semibold)).tracking(0.6).foregroundStyle(Fluid.mutedForeground)
    }

    private struct GalleryRow: Identifiable {
        let id: Int
        let title: String
        let detail: String
    }
}

public enum FluidGallerySnapshot {
    @MainActor
    public static func render() async -> NSBitmapImageRep? {
        let host = NSHostingView(rootView: FluidGallery())
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        try? await Task.sleep(for: .milliseconds(600))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }
}
