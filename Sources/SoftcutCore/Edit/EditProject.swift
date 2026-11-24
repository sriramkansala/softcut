import Foundation

/// Another recording added to a project. It brings its own zooms and masks, which are tied to moments
/// of that recording, so they follow its clips wherever they are put in the video.
public struct AttachedSource: Equatable, Codable, Identifiable, Sendable {
    public var id: UUID
    /// The recording's folder.
    public var path: String
    public var name: String
    /// Length of the recording, kept so the project can be edited even if the folder is later moved.
    public var duration: Double
    public var zooms: [ZoomSegment]
    public var masks: [MaskRegion]

    public var folder: URL { URL(fileURLWithPath: path, isDirectory: true) }

    public init(id: UUID = UUID(), path: String, name: String, duration: Double, zooms: [ZoomSegment] = [], masks: [MaskRegion] = []) {
        self.id = id
        self.path = path
        self.name = name
        self.duration = duration
        self.zooms = zooms
        self.masks = masks
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        path = try c.decode(String.self, forKey: .path)
        name = c.value(.name, URL(fileURLWithPath: path).lastPathComponent)
        duration = c.value(.duration, 0)
        zooms = c.value(.zooms, [])
        masks = c.value(.masks, [])
    }
}

/// Everything a person can change about how recordings become a video. It starts as the automatic edit
/// and is saved next to the recording as `edit.json`, so edits survive closing the editor and the raw
/// recordings are never touched.
///
/// The video is the `slices` end to end, in list order. Each slice is a stretch of one recording: the
/// project's own recording (`sourceID` nil) or one that was attached.
public struct EditProject: Equatable, Codable, Sendable {
    public var formatVersion = 2
    public var settings = EditSettings()
    /// Zooms on the project's own recording, in its time, sorted and not overlapping.
    public var zooms: [ZoomSegment] = []
    /// The clips of the video, in order. Gaps in a recording between its clips are not in the video.
    public var slices: [TimeSegment] = []
    public var audio = AudioSettings()
    /// Regions of the project's own recording that are hidden for a while. They may overlap each other.
    public var masks: [MaskRegion] = []
    /// Recordings added to this project.
    public var attachments: [AttachedSource] = []
    /// Captions for every recording in the project, each in its own recording's time.
    public var captions: [CaptionLine] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = c.value(.formatVersion, formatVersion)
        settings = c.value(.settings, settings)
        zooms = c.value(.zooms, zooms)
        slices = c.value(.slices, slices)
        audio = c.value(.audio, audio)
        masks = c.value(.masks, masks)
        attachments = c.value(.attachments, attachments)
        captions = c.value(.captions, captions)
    }

    static let fileName = "edit.json"

    /// The edit Softcut makes on its own: zooms from clicks and typing, and idle ends trimmed.
    public static func auto(for bundle: RecordingBundle, settings: EditSettings = EditSettings()) -> EditProject {
        let input = bundle.input
        let duration = bundle.manifest.duration
        let hasAudio = bundle.manifest.hasMicrophone || bundle.manifest.hasSystemAudio
        // Clicks in the trimmed tail (the stop button) must not trigger a zoom.
        let keptEnd = max(1, duration - settings.trimTail)
        let keys = settings.zoomOnTyping ? input.keys.filter { $0.t <= keptEnd } : []

        var project = EditProject()
        project.settings = settings
        if settings.autoZoom {
            project.zooms = AutoEditor.planZooms(clicks: input.clicks.filter { $0.t <= keptEnd }, keys: keys,
                                                 focus: input.focus, moves: input.moves, duration: keptEnd, settings: settings)
        }
        // Without key times, typing looks like a quiet mouse, so idle trimming would cut it out.
        project.slices = AutoEditor.planTime(input: input, duration: duration, hasAudio: hasAudio,
                                             hasVoice: bundle.manifest.hasMicrophone,
                                             typingTracked: bundle.manifest.keysCaptured ?? false,
                                             settings: settings).segments
        if project.slices.isEmpty { project.slices = [TimeSegment(sourceStart: 0, sourceEnd: duration)] }
        return project
    }

    // MARK: Saving

    /// The saved edit for a recording, or nil if there is none or it cannot be read.
    public static func load(from folder: URL) -> EditProject? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(fileName)) else { return nil }
        return try? JSONDecoder().decode(EditProject.self, from: data)
    }

    /// Writes the project. Recordings that no clip uses are left out of the file.
    public func save(to folder: URL) throws {
        var tidy = self
        tidy.pruneUnusedAttachments()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(tidy).write(to: folder.appendingPathComponent(Self.fileName), options: .atomic)
    }

    /// The saved edit if there is one, otherwise the automatic edit.
    public static func open(_ bundle: RecordingBundle) -> EditProject {
        guard var project = load(from: bundle.folder) else { return auto(for: bundle) }
        project.upgrade(for: bundle)
        return project
    }

    /// Projects saved before version 2 start each automatic zoom 0.6 s before its click, which left the picture still
    /// moving when the click landed. Zooms that still start exactly there move to the new lead; any moved by hand stay.
    mutating func upgrade(for bundle: RecordingBundle) {
        guard formatVersion < 2 else { return }
        formatVersion = 2
        let oldLead = 0.6
        guard settings.clickZoomLead == oldLead else { return }
        settings.clickZoomLead = EditSettings().clickZoomLead
        let presses = AutoEditor.presses(bundle.input.clicks)
        for index in zooms.indices {
            guard let press = presses.first(where: { abs($0.down - oldLead - zooms[index].start) < 0.002 }) else { continue }
            let earliest = index > 0 ? zooms[index - 1].end : 0
            zooms[index].start = max(earliest, press.down - settings.clickZoomLead)
        }
    }

    public var timeMap: TimeMap { TimeMap(segments: slices) }
}

// MARK: Recordings

public extension EditProject {
    func attachment(_ id: UUID?) -> AttachedSource? { id.flatMap { id in attachments.first { $0.id == id } } }

    /// Adds a recording and puts its clips at the end of the video.
    mutating func attach(_ source: AttachedSource, clips: [TimeSegment]) {
        attachments.append(source)
        slices.append(contentsOf: clips.map { var clip = $0; clip.sourceID = source.id; return clip })
    }

    /// Drops attached recordings that no clip uses any more.
    mutating func pruneUnusedAttachments() {
        let used = Set(slices.compactMap(\.sourceID))
        attachments.removeAll { !used.contains($0.id) }
    }

    /// Length of a recording. The project's own recording is passed in; attached ones remember theirs.
    func duration(of source: UUID?, primary: Double) -> Double {
        source == nil ? primary : (attachment(source)?.duration ?? 0)
    }

    func zooms(of source: UUID?) -> [ZoomSegment] { source == nil ? zooms : (attachment(source)?.zooms ?? []) }
    func masks(of source: UUID?) -> [MaskRegion] { source == nil ? masks : (attachment(source)?.masks ?? []) }

    mutating func modifyZooms(of source: UUID?, _ body: (inout [ZoomSegment]) -> Void) {
        if source == nil { body(&zooms); return }
        guard let index = attachments.firstIndex(where: { $0.id == source }) else { return }
        body(&attachments[index].zooms)
    }

    mutating func modifyMasks(of source: UUID?, _ body: (inout [MaskRegion]) -> Void) {
        if source == nil { body(&masks); return }
        guard let index = attachments.firstIndex(where: { $0.id == source }) else { return }
        body(&attachments[index].masks)
    }

    /// Which recording a zoom belongs to, and where it is in that recording's list.
    func locateZoom(_ id: UUID) -> (source: UUID?, index: Int)? {
        if let index = zooms.firstIndex(where: { $0.id == id }) { return (nil, index) }
        for attachment in attachments {
            if let index = attachment.zooms.firstIndex(where: { $0.id == id }) { return (attachment.id, index) }
        }
        return nil
    }

    func locateMask(_ id: UUID) -> (source: UUID?, index: Int)? {
        if let index = masks.firstIndex(where: { $0.id == id }) { return (nil, index) }
        for attachment in attachments {
            if let index = attachment.masks.firstIndex(where: { $0.id == id }) { return (attachment.id, index) }
        }
        return nil
    }
}

// MARK: Editing zooms

public extension EditProject {
    static let minimumZoomLength = 0.5

    func zoom(_ id: UUID?) -> ZoomSegment? {
        guard let id, let found = locateZoom(id) else { return nil }
        return zooms(of: found.source)[found.index]
    }

    /// Adds a zoom of about `length` seconds at `time` in a recording, squeezed into the free space around it.
    /// Returns nil when there is no room (the moment is already inside a zoom, or the gap is too small).
    @discardableResult
    mutating func addZoom(source: UUID? = nil, at time: Double, recordingDuration: Double, aim: SIMD2<Double>, scale: Double, length: Double = 2.5) -> UUID? {
        let existing = zooms(of: source)
        guard !existing.contains(where: { time >= $0.start && time <= $0.end }) else { return nil }
        let before = existing.filter { $0.end <= time }.map(\.end).max() ?? 0
        let after = existing.filter { $0.start >= time }.map(\.start).min() ?? recordingDuration
        let start = max(before, time - length * 0.25)
        let end = min(after, start + length)
        guard end - start >= Self.minimumZoomLength else { return nil }
        let zoom = ZoomSegment(start: start, end: end, focusX: aim.x, focusY: aim.y, focusTime: start, scale: scale)
        modifyZooms(of: source) { list in
            list.append(zoom)
            list.sort { $0.start < $1.start }
        }
        return zoom.id
    }

    /// Moves or resizes a zoom, keeping it inside its recording and clear of its neighbours.
    mutating func setZoomRange(_ id: UUID, start: Double, end: Double, recordingDuration: Double) {
        guard let found = locateZoom(id) else { return }
        modifyZooms(of: found.source) { zooms in
            guard let index = zooms.firstIndex(where: { $0.id == id }) else { return }
            let lower = index > 0 ? zooms[index - 1].end : 0
            let upper = index + 1 < zooms.count ? zooms[index + 1].start : recordingDuration
            var newStart = min(max(start, lower), upper - Self.minimumZoomLength)
            var newEnd = max(min(end, upper), newStart + Self.minimumZoomLength)
            newEnd = min(newEnd, upper)
            newStart = min(newStart, newEnd - Self.minimumZoomLength)
            zooms[index].start = newStart
            zooms[index].end = newEnd
            // The camera is on the focus point by the time the zoom begins.
            zooms[index].focusTime = min(max(zooms[index].focusTime, newStart), newEnd)
        }
    }

    /// Moves a whole zoom by `delta` seconds without changing its length.
    mutating func moveZoom(_ id: UUID, by delta: Double, recordingDuration: Double) {
        guard let zoom = zoom(id), let found = locateZoom(id) else { return }
        let list = zooms(of: found.source)
        let length = zoom.end - zoom.start
        let lower = found.index > 0 ? list[found.index - 1].end : 0
        let upper = found.index + 1 < list.count ? list[found.index + 1].start : recordingDuration
        let start = min(max(zoom.start + delta, lower), upper - length)
        guard start >= lower else { return }
        setZoomRange(id, start: start, end: start + length, recordingDuration: recordingDuration)
    }

    mutating func deleteZoom(_ id: UUID) {
        guard let found = locateZoom(id) else { return }
        modifyZooms(of: found.source) { $0.removeAll { $0.id == id } }
    }

    mutating func updateZoom(_ id: UUID, _ change: (inout ZoomSegment) -> Void) {
        guard let found = locateZoom(id) else { return }
        modifyZooms(of: found.source) { zooms in
            if let index = zooms.firstIndex(where: { $0.id == id }) { change(&zooms[index]) }
        }
    }

    /// Replaces a recording's zooms with the ones Softcut would choose by itself.
    mutating func regenerateZooms(for bundle: RecordingBundle, source: UUID? = nil) {
        let fresh = EditProject.auto(for: bundle, settings: settings).zooms
        modifyZooms(of: source) { $0 = fresh }
    }
}

// MARK: Editing masks

public extension EditProject {
    func mask(_ id: UUID?) -> MaskRegion? {
        guard let id, let found = locateMask(id) else { return nil }
        return masks(of: found.source)[found.index]
    }

    /// Adds a mask at `time` in a recording, lasting `length` seconds, over a rectangle in the middle of the screen.
    @discardableResult
    mutating func addMask(source: UUID? = nil, at time: Double, recordingDuration: Double, length: Double = 3, rect: CropRect? = nil) -> UUID {
        let start = min(max(0, time), max(0, recordingDuration - MaskRegion.minimumLength))
        let end = min(recordingDuration, start + length)
        let mask = MaskRegion(start: start, end: max(end, start + MaskRegion.minimumLength),
                              rect: rect ?? CropRect(x: 0.35, y: 0.4, width: 0.3, height: 0.2))
        modifyMasks(of: source) { list in
            list.append(mask)
            list.sort { $0.start < $1.start }
        }
        return mask.id
    }

    mutating func setMaskRange(_ id: UUID, start: Double, end: Double, recordingDuration: Double) {
        guard let found = locateMask(id) else { return }
        var newStart = min(max(start, 0), recordingDuration - MaskRegion.minimumLength)
        let newEnd = min(max(end, newStart + MaskRegion.minimumLength), recordingDuration)
        newStart = min(newStart, newEnd - MaskRegion.minimumLength)
        modifyMasks(of: found.source) { masks in
            guard let index = masks.firstIndex(where: { $0.id == id }) else { return }
            masks[index].start = newStart
            masks[index].end = newEnd
        }
    }

    /// Moves a whole mask by `delta` seconds without changing its length, keeping it inside the recording.
    mutating func moveMask(_ id: UUID, by delta: Double, recordingDuration: Double) {
        guard let mask = mask(id) else { return }
        let length = mask.end - mask.start
        let start = min(max(mask.start + delta, 0), max(0, recordingDuration - length))
        setMaskRange(id, start: start, end: start + length, recordingDuration: recordingDuration)
    }

    mutating func updateMask(_ id: UUID, _ change: (inout MaskRegion) -> Void) {
        guard let found = locateMask(id) else { return }
        modifyMasks(of: found.source) { masks in
            guard let index = masks.firstIndex(where: { $0.id == id }) else { return }
            change(&masks[index])
            masks[index].rect = masks[index].rect.clamped(minimum: MaskRegion.minimumSize)
        }
    }

    mutating func deleteMask(_ id: UUID) {
        guard let found = locateMask(id) else { return }
        modifyMasks(of: found.source) { $0.removeAll { $0.id == id } }
    }
}

// MARK: Editing clips

public extension EditProject {
    static let minimumSliceLength = 0.2

    func slice(_ id: UUID?) -> TimeSegment? { id.flatMap { id in slices.first { $0.id == id } } }

    func sliceIndex(_ id: UUID?) -> Int? { id.flatMap { id in slices.firstIndex { $0.id == id } } }

    /// Splits the clip of a recording that is showing `time`, in two. Both halves keep the same speed.
    @discardableResult
    mutating func split(at time: Double, source: UUID? = nil) -> Bool {
        guard let clip = slices.first(where: { $0.sourceID == source && time > $0.sourceStart + Self.minimumSliceLength && time < $0.sourceEnd - Self.minimumSliceLength }) else {
            return false
        }
        return split(clipID: clip.id, atSource: time)
    }

    @discardableResult
    mutating func split(clipID: UUID, atSource time: Double) -> Bool {
        guard let index = slices.firstIndex(where: { $0.id == clipID }),
              time > slices[index].sourceStart + Self.minimumSliceLength,
              time < slices[index].sourceEnd - Self.minimumSliceLength else { return false }
        var second = slices[index]
        second.id = UUID()
        second.sourceStart = time
        slices[index].sourceEnd = time
        slices.insert(second, at: index + 1)
        return true
    }

    /// Cuts a clip out of the video. The last remaining clip cannot be deleted.
    /// The recording the clip came from stays in the project even if this was its last clip, so the clip can be
    /// pasted back; unused recordings are dropped when the project is saved.
    mutating func deleteSlice(_ id: UUID) {
        guard slices.count > 1 else { return }
        slices.removeAll { $0.id == id }
    }

    /// Trims a clip by moving the ends of the stretch it shows, keeping it inside its recording and clear of the
    /// neighbouring stretches of the same recording.
    mutating func setSliceRange(_ id: UUID, start: Double, end: Double, recordingDuration: Double) {
        guard let index = slices.firstIndex(where: { $0.id == id }) else { return }
        let clip = slices[index]
        let others = slices.enumerated().filter { $0.offset != index && $0.element.sourceID == clip.sourceID }.map(\.element)
        let lower = others.filter { $0.sourceEnd <= clip.sourceStart + 0.0001 }.map(\.sourceEnd).max() ?? 0
        let upper = others.filter { $0.sourceStart >= clip.sourceEnd - 0.0001 }.map(\.sourceStart).min() ?? recordingDuration
        let newStart = min(max(start, lower), upper - Self.minimumSliceLength)
        let newEnd = min(max(end, newStart + Self.minimumSliceLength), upper)
        slices[index].sourceStart = newStart
        slices[index].sourceEnd = max(newEnd, newStart + Self.minimumSliceLength)
    }

    mutating func updateSlice(_ id: UUID, _ change: (inout TimeSegment) -> Void) {
        guard let index = slices.firstIndex(where: { $0.id == id }) else { return }
        change(&slices[index])
    }

    mutating func setSliceSpeed(_ id: UUID, _ speed: Double) {
        guard let index = slices.firstIndex(where: { $0.id == id }) else { return }
        slices[index].speed = min(max(speed, 0.25), 16)
    }

    /// Moves a clip to another place in the video. `index` counts the clips with this one taken out.
    mutating func moveSlice(_ id: UUID, toIndex index: Int) {
        guard let from = slices.firstIndex(where: { $0.id == id }) else { return }
        let clip = slices.remove(at: from)
        slices.insert(clip, at: min(max(0, index), slices.count))
    }

    /// Puts copies of clips into the video at `index`, with fresh identities. Returns the new clips' ids.
    @discardableResult
    mutating func insertSlices(_ clips: [TimeSegment], at index: Int) -> [UUID] {
        let copies = clips.map { clip -> TimeSegment in var copy = clip; copy.id = UUID(); return copy }
        slices.insert(contentsOf: copies, at: min(max(0, index), slices.count))
        return copies.map(\.id)
    }

    /// Brings back everything that was trimmed or cut: each recording used in the video becomes one clip
    /// at normal speed, in the order they first appear.
    mutating func restoreAllSlices(recordingDuration: Double) {
        var order: [UUID?] = []
        for clip in slices where !order.contains(where: { $0 == clip.sourceID }) { order.append(clip.sourceID) }
        if order.isEmpty { order = [nil] }
        slices = order.map { source in
            TimeSegment(sourceID: source, sourceStart: 0, sourceEnd: duration(of: source, primary: recordingDuration))
        }
    }
}
