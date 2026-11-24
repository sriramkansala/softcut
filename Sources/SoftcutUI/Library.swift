import AVFoundation
import AppKit
import SoftcutCore
import SwiftUI

public struct RecordingItem: Identifiable, Hashable {
    public let folder: URL
    public var id: URL { folder }
    public let name: String
    public let createdAt: Date
    public let duration: Double
    public let hasWebcam: Bool
    public let isEdited: Bool
}

/// The recordings kept on disk, newest first.
@MainActor
public final class RecordingLibrary: ObservableObject {
    @Published public private(set) var items: [RecordingItem] = []
    public let root: URL

    public init(root: URL) {
        self.root = root
        reload()
    }

    public func reload() {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        items = folders.compactMap { folder -> RecordingItem? in
            guard let bundle = try? RecordingBundle.load(from: folder) else { return nil }
            return RecordingItem(folder: folder, name: folder.lastPathComponent, createdAt: bundle.manifest.createdAt,
                                 duration: bundle.manifest.duration, hasWebcam: bundle.webcamURL != nil,
                                 isEdited: FileManager.default.fileExists(atPath: folder.appendingPathComponent("edit.json").path))
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    public func moveToTrash(_ item: RecordingItem) {
        try? FileManager.default.trashItem(at: item.folder, resultingItemURL: nil)
        reload()
    }
}

/// Every recording as a card, filtered from a sidebar; opening one starts the editor.
public struct LibraryView: View {
    @ObservedObject var library: RecordingLibrary
    let open: (RecordingItem) -> Void
    let record: () -> Void

    @State private var filter = LibraryFilter.all
    @State private var query = ""
    @State private var sidebarOpen = true
    @State private var sidebarWidth: CGFloat = 220
    @State private var trashing: RecordingItem?

    public init(library: RecordingLibrary, open: @escaping (RecordingItem) -> Void, record: @escaping () -> Void) {
        self.library = library
        self.open = open
        self.record = record
    }

    private var shown: [RecordingItem] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        return library.items.filter { item in filter.includes(item) && words.allSatisfy { item.name.lowercased().contains($0) } }
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(spacing: 0) {
            // The title bar row: the window's buttons, the sidebar switch, and the main actions.
            HStack(spacing: 8) {
                Color.clear.frame(width: 66, height: 1)
                FluidSidebarTrigger(isOpen: $sidebarOpen)
                Spacer()
                SearchField(text: $query, placeholder: "Search recordings").frame(width: 260)
                FluidIconButton(systemName: "arrow.clockwise", help: "Refresh") { library.reload() }
                FluidButton("New recording", icon: "record.circle", variant: .accent) { record() }
            }
            .padding(.horizontal, 12)
            .frame(height: 54)

            HStack(alignment: .top, spacing: 10) {
                if sidebarOpen {
                    VStack(alignment: .leading, spacing: 0) {
                        FluidSidebarMenu(sections: [FluidSidebarSection(title: "Recordings", items: LibraryFilter.allCases.map { item in
                            FluidSidebarItem(id: item, title: item.title, icon: item.icon, badge: "\(library.items.filter(item.includes).count)")
                        })], selection: $filter)
                        Spacer()
                    }
                    .frame(width: 230)
                    .frame(maxHeight: .infinity)
                    .background(Theme.panel, in: shape)
                    .overlay(shape.strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }

                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Text(filter.title).font(Fluid.font(.title, .semibold, density: .regular)).foregroundStyle(Fluid.foreground)
                        FluidBadge(text: "\(shown.count)")
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 52)
                    Rectangle().fill(Fluid.border).frame(height: 1).padding(.horizontal, 18)

                    if shown.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "film.stack").font(.system(size: 32)).foregroundStyle(Fluid.mutedForeground)
                            Text(library.items.isEmpty ? "No recordings yet" : "Nothing matches")
                                .font(Fluid.font(.title, .semibold, density: .regular)).foregroundStyle(Fluid.foreground)
                            Text(library.items.isEmpty ? "Press Control + Option + R to start and stop a recording. It opens here to edit."
                                                       : "Try another filter or search.")
                                .font(Fluid.font(.body, density: .regular)).foregroundStyle(Fluid.mutedForeground)
                            if library.items.isEmpty {
                                FluidButton("New recording", icon: "record.circle", variant: .raised, size: .regular) { record() }.padding(.top, 6)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        FluidScrollArea {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210, maximum: 300), spacing: 14)], spacing: 18) {
                                ForEach(shown) { item in
                                    RecordingCard(item: item, open: { open(item) }, trash: { trashing = item })
                                }
                            }
                            .padding(18)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.panel, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
                .clipShape(shape)
            }
            .padding([.horizontal, .bottom], 10)
        }
        .environment(\.fluidSurfaceLevel, 2)
        .frame(minWidth: 720, minHeight: 460)
        .background(Theme.canvas)
        .ignoresSafeArea(.container, edges: .top)
        .preferredColorScheme(.dark)
        .fluidDialog(isPresented: Binding(get: { trashing != nil }, set: { if !$0 { trashing = nil } }),
                     title: "Move “\(trashing?.name ?? "")” to the Trash?",
                     description: "The recording and its edit go to the Trash. You can put them back from there.") {
            EmptyView()
        } footer: {
            FluidButton("Cancel", variant: .ghost) { trashing = nil }
            FluidButton("Move to Trash", icon: "trash", variant: .primary) {
                if let item = trashing { library.moveToTrash(item) }
                trashing = nil
            }
        }
    }
}

enum LibraryFilter: String, CaseIterable, Hashable {
    case all, edited, webcam, week

    var title: String {
        switch self {
        case .all: return "All recordings"
        case .edited: return "Edited"
        case .webcam: return "With webcam"
        case .week: return "This week"
        }
    }

    var icon: String {
        switch self {
        case .all: return "film.stack"
        case .edited: return "slider.horizontal.3"
        case .webcam: return "web.camera"
        case .week: return "calendar"
        }
    }

    func includes(_ item: RecordingItem) -> Bool {
        switch self {
        case .all: return true
        case .edited: return item.isEdited
        case .webcam: return item.hasWebcam
        case .week: return item.createdAt > Date().addingTimeInterval(-7 * 24 * 3600)
        }
    }
}

/// A recording as a Fluid card: its first frame, name and length, with badges for what it has. It lights on hover,
/// opens on a double click, and offers its actions in a menu.
private struct RecordingCard: View {
    let item: RecordingItem
    let open: () -> Void
    let trash: () -> Void
    @State private var thumbnail: CGImage?
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.white.opacity(0.04)
                .aspectRatio(16.0 / 10, contentMode: .fit)
                .overlay {
                    if let thumbnail {
                        Image(decorative: thumbnail, scale: 1).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "film").font(.title2).foregroundStyle(Fluid.mutedForeground)
                    }
                }
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(hovered ? 0.18 : 0.08), lineWidth: 1))
                .overlay(alignment: .bottomLeading) {
                    Text(timecode(item.duration, tenths: false))
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .padding(8)
                }
                .overlay(alignment: .topTrailing) {
                    FluidDropdown(rows: {
                        [.item("Open", icon: "slider.horizontal.3") { open() },
                         .item("Show in Finder", icon: "folder") { NSWorkspace.shared.activateFileViewerSelecting([item.folder]) },
                         .separator(),
                         .item("Move to Trash…", icon: "trash", destructive: true) { trash() }]
                    }, width: 200, placement: .belowTrailing) { isOpen in
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .opacity(hovered || isOpen ? 1 : 0)
                    }
                    .padding(8)
                }

            VStack(alignment: .leading, spacing: 5) {
                Text(item.name).font(.system(size: 12, weight: .medium)).foregroundStyle(Fluid.foreground).lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.createdAt, format: .dateTime.month(.abbreviated).day())
                        .font(Fluid.font(.caption)).foregroundStyle(Fluid.mutedForeground)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if item.hasWebcam { FluidBadge(text: "Webcam", color: .green) }
                    if item.isEdited { FluidBadge(text: "Edited", color: .violet) }
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(6)
        .background(hovered ? Fluid.hover : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.08), value: hovered)
        .onTapGesture(count: 2) { open() }
        .contextMenu {
            Button("Open") { open() }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.folder]) }
            Divider()
            Button("Move to Trash…", role: .destructive) { trash() }
        }
        .task(id: item.folder) { thumbnail = await Self.makeThumbnail(item.folder) }
    }

    private static func makeThumbnail(_ folder: URL) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: folder.appendingPathComponent("screen.mov")))
        generator.maximumSize = CGSize(width: 640, height: 640)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 2, preferredTimescale: 600)
        return try? await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image
    }
}
