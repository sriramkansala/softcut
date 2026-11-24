import Foundation

/// The recordings a project is made of, loaded: its own and any that were attached.
public struct SourceSet {
    public let primary: RecordingBundle
    public private(set) var attached: [UUID: RecordingBundle]

    public init(primary: RecordingBundle, attached: [UUID: RecordingBundle] = [:]) {
        self.primary = primary
        self.attached = attached
    }

    /// Loads the recordings a project refers to. One that cannot be found or read is left out.
    public static func load(primary: RecordingBundle, project: EditProject) -> SourceSet {
        var set = SourceSet(primary: primary)
        for attachment in project.attachments {
            if let bundle = try? RecordingBundle.load(from: attachment.folder) { set.attached[attachment.id] = bundle }
        }
        return set
    }

    /// Whether any of the recordings has a webcam picture.
    public var hasWebcam: Bool { primary.webcamURL != nil || attached.values.contains { $0.webcamURL != nil } }

    public func bundle(_ id: UUID?) -> RecordingBundle? { id == nil ? primary : attached[id!] }

    public mutating func add(_ bundle: RecordingBundle, as id: UUID) { attached[id] = bundle }

    /// Attached recordings of a project that could not be loaded.
    public func missing(in project: EditProject) -> [AttachedSource] {
        project.attachments.filter { attached[$0.id] == nil }
    }

    /// Whether every recording that the project's clips use is available.
    public func covers(_ project: EditProject) -> Bool {
        project.slices.allSatisfy { bundle($0.sourceID) != nil }
    }
}
