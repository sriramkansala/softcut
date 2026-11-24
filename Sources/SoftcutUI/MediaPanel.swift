import AVFoundation
import AppKit
import SoftcutCore
import SwiftUI

/// The tabs of the panel on the editor's left.
public enum EditorSideTab: String, CaseIterable {
    case media, chat, mockups

    var title: String {
        switch self {
        case .media: return "Media"
        case .chat: return "Chat"
        case .mockups: return "Mockups"
        }
    }
}

/// The panel on the editor's left: the recordings, a chat that makes edits, and the 3D devices.
struct SidePanel: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var chat: EditorChat
    let projectMenu: ProjectMenu?
    @Binding var tab: EditorSideTab
    let hide: () -> Void

    @State private var query = ""
    @State private var order = MediaPanel.MediaOrder.newest

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(spacing: 0) {
            // The window's close, minimize and zoom buttons sit on this line, in the panel's corner.
            FluidIconButton(systemName: "sidebar.left", help: "Hide the side panel", action: hide)
                .padding(.trailing, 8)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .frame(height: 36)
            FluidTabs(selection: $tab, items: EditorSideTab.allCases.map { FluidTabItem($0, $0.title) }, fill: true)
                .padding(.horizontal, 12)
            // All three stay alive, so that coming back to one finds it as it was, already laid out.
            ZStack(alignment: .top) {
                panel(.media) { MediaPanel(model: model, projectMenu: projectMenu, query: $query, order: $order) }
                panel(.chat) { ChatPanel(model: model, chat: chat) }
                panel(.mockups) { MockupsPanel(model: model) }
            }
            .animation(.easeOut(duration: 0.1), value: tab)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.panel, in: shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
        .clipShape(shape)
        .environment(\.fluidSurfaceLevel, 2)
    }

    private func panel<Content: View>(_ side: EditorSideTab, @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(tab == side ? 1 : 0)
            .allowsHitTesting(tab == side)
            .accessibilityHidden(tab != side)
    }
}

/// The Media tab: the recordings in this video, and the other recordings that could be added to it, as a grid of
/// stills with their lengths.
struct MediaPanel: View {
    @ObservedObject var model: EditorModel
    let projectMenu: ProjectMenu?
    @Binding var query: String
    @Binding var order: MediaOrder

    enum MediaOrder: String, CaseIterable {
        case newest, oldest, name, length
        var title: String {
            switch self {
            case .newest: return "Newest first"
            case .oldest: return "Oldest first"
            case .name: return "By name"
            case .length: return "Longest first"
            }
        }
    }

    private struct Tile: Identifiable {
        let id: String
        let name: String
        let folder: URL
        let duration: Double
        let createdAt: Date
        /// The recording's id in this project (nil for the main one), or no value for a recording not in it.
        let source: UUID??
    }

    private var inVideo: [Tile] {
        var tiles = [Tile(id: "main", name: model.title, folder: model.bundle.folder, duration: model.bundle.manifest.duration,
                          createdAt: model.bundle.manifest.createdAt, source: .some(nil))]
        tiles += model.project.attachments.map {
            Tile(id: $0.id.uuidString, name: $0.name, folder: $0.folder, duration: $0.duration, createdAt: .distantPast, source: .some($0.id))
        }
        return filtered(tiles, sorting: false)
    }

    private var others: [Tile] {
        let candidates = model.addable(projectMenu?.projects ?? []).map {
            Tile(id: $0.folder.path, name: $0.name, folder: $0.folder, duration: $0.duration, createdAt: $0.createdAt, source: nil)
        }
        return filtered(candidates, sorting: true)
    }

    private func filtered(_ tiles: [Tile], sorting: Bool) -> [Tile] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        let matching = tiles.filter { tile in words.allSatisfy { tile.name.lowercased().contains($0) } }
        guard sorting else { return matching }
        switch order {
        case .newest: return matching.sorted { $0.createdAt > $1.createdAt }
        case .oldest: return matching.sorted { $0.createdAt < $1.createdAt }
        case .name: return matching.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .length: return matching.sorted { $0.duration > $1.duration }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                SearchField(text: $query, placeholder: "Search recordings")
                FluidDropdown(rows: {
                    MediaOrder.allCases.map { item in .item(item.title, checked: item == order) { order = item } }
                }, width: 180, placement: .belowTrailing) { open in
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(open ? Fluid.foreground : Fluid.mutedForeground)
                        .frame(width: 36, height: 36)
                        .background(open ? Fluid.active : Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .fluidTooltip("Sort the recordings")
            }
            .padding(12)

            FluidScrollArea {
                VStack(alignment: .leading, spacing: 16) {
                    section("In this video", tiles: inVideo)
                    let others = others
                    if !others.isEmpty || !query.isEmpty {
                        section("Your other recordings", tiles: others)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }

            Button { chooseFolder() } label: {
                Label("Add a recording…", systemImage: "plus")
            }
            .buttonStyle(FluidButtonStyle(variant: .raised, size: .regular, fullWidth: true))
            .padding(12)
            .fluidTooltip("Add a recording folder to the end of this video")
        }
    }

    @ViewBuilder
    private func section(_ title: String, tiles: [Tile]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Fluid.font(.caption, .semibold)).foregroundStyle(Fluid.mutedForeground)
            if tiles.isEmpty {
                HelpText(query.isEmpty ? "Nothing here yet." : "Nothing matches “\(query)”.")
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 12) {
                    ForEach(tiles) { tile in
                        MediaTile(name: tile.name, folder: tile.folder, duration: tile.duration, isInVideo: tile.source != nil,
                                  isMain: tile.id == "main",
                                  action: {
                                      if let source = tile.source { jump(to: source) } else { attach(tile.folder) }
                                  })
                    }
                }
            }
        }
    }

    /// Moves the playhead to the first clip from a recording.
    private func jump(to source: UUID?) {
        let timeMap = model.project.timeMap
        if let index = timeMap.segments.firstIndex(where: { $0.sourceID == source }) {
            model.selection = .slice(timeMap.segments[index].id)
            model.seek(toOutput: timeMap.outputStarts[index])
        }
    }

    private func attach(_ folder: URL) {
        do { try model.attachRecording(from: folder) } catch { model.notice = error.localizedDescription }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a Softcut recording folder to add to the video"
        panel.directoryURL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
        if panel.runModal() == .OK, let url = panel.url { attach(url) }
    }
}

/// A filled search field with a magnifier, as in the reference's media panel.
struct SearchField: View {
    @Binding var text: String
    var placeholder: String
    @FocusState private var focused: Bool
    @State private var hovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: focused ? .semibold : .regular))
                .foregroundStyle(focused || hovered ? Fluid.foreground : Fluid.mutedForeground)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Fluid.mutedForeground))
                .textFieldStyle(.plain)
                .font(Fluid.font(.body, density: .regular))
                .foregroundStyle(Fluid.foreground)
                .focused($focused)
                .onSubmit { focused = false }
                .onExitCommand { focused = false }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(Fluid.mutedForeground)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear the search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(focused ? Fluid.card : Color.white.opacity(hovered ? 0.06 : 0.045), in: shape)
        .overlay(shape.strokeBorder(focused ? Fluid.border : .clear, lineWidth: 1))
        .contentShape(shape)
        .onTapGesture { focused = true }
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.08), value: focused)
    }
}

/// A recording as a still with its length on a dark pill, and its name underneath. A recording already in the video
/// jumps to its first clip; another one shows an Add button on hover.
private struct MediaTile: View {
    let name: String
    let folder: URL
    let duration: Double
    let isInVideo: Bool
    let isMain: Bool
    let action: () -> Void

    @State private var thumbnail: CGImage?
    @State private var hovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(alignment: .leading, spacing: 6) {
            Color.white.opacity(0.04)
                .aspectRatio(16.0 / 11, contentMode: .fit)
                .overlay {
                    if let thumbnail {
                        Image(decorative: thumbnail, scale: 1).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "film").foregroundStyle(Fluid.mutedForeground)
                    }
                }
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.white.opacity(hovered ? 0.18 : 0.08), lineWidth: 1))
                .overlay(alignment: .bottomLeading) {
                    Text(timecode(duration, tenths: false))
                        .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(6)
                }
                .overlay(alignment: .topTrailing) {
                    if isMain {
                        FluidBadge(text: "Main", color: .violet).padding(6)
                    } else if !isInVideo && hovered {
                        HStack(spacing: 4) {
                            Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                            Text("Add").font(.system(size: 10.5, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(LinearGradient(colors: [Brand.light, Brand.deep], startPoint: .top, endPoint: .bottom),
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(6)
                        .transition(.opacity.animation(Fluid.Motion.fast))
                    }
                }
            Text(name)
                .font(.system(size: 11))
                .foregroundStyle(hovered ? Fluid.foreground : Fluid.mutedForeground)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.leading, 2)
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture(perform: action)
        .animation(.easeOut(duration: 0.08), value: hovered)
        .fluidTooltip(isInVideo ? "Go to this recording in the video" : "Add to the end of this video")
        .task(id: folder) { thumbnail = await Self.still(folder) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(timecode(duration, tenths: false))")
        .accessibilityAddTraits(.isButton)
    }

    static func still(_ folder: URL) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: folder.appendingPathComponent("screen.mov")))
        generator.maximumSize = CGSize(width: 480, height: 480)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 2, preferredTimescale: 600)
        return try? await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image
    }
}
