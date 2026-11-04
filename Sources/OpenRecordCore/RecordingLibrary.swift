import Foundation

public enum LibraryError: LocalizedError, Equatable {
    case invalidID(String)
    case notFound(String)
    case empty

    public var errorDescription: String? {
        switch self {
        case .invalidID(let id): "Invalid recording id: \(id)"
        case .notFound(let id): "No recording with id \(id)"
        case .empty: "There are no recordings yet"
        }
    }
}

/// Recordings live on disk as one folder per recording:
/// `<root>/<id>/{meta.json, recording.mp4, transcript.json}`.
/// The menu bar app writes; the MCP server only reads.
public struct RecordingLibrary: Sendable {
    public static let latestAlias = "latest"

    public let root: URL

    public init(root: URL = RecordingLibrary.defaultRoot()) {
        self.root = root
    }

    public static func defaultRoot() -> URL {
        if let override = ProcessInfo.processInfo.environment["OPENRECORD_LIBRARY"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies/OpenRecord", isDirectory: true)
    }

    public func folder(for id: String) -> URL {
        root.appendingPathComponent(id, isDirectory: true)
    }

    public func videoURL(for recording: Recording) -> URL {
        folder(for: recording.id).appendingPathComponent(recording.videoFile)
    }

    public func createRecording(at date: Date = .now) throws -> Recording {
        // meta.json stores ISO 8601 without fractional seconds; truncate so reloads compare equal.
        let date = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let baseID = Self.idFormatter.string(from: date)
        var id = baseID
        var suffix = 2
        while FileManager.default.fileExists(atPath: folder(for: id).path) {
            id = "\(baseID)-\(suffix)"
            suffix += 1
        }
        try FileManager.default.createDirectory(at: folder(for: id), withIntermediateDirectories: false)
        let recording = Recording(
            id: id,
            title: "Recording \(date.formatted(date: .abbreviated, time: .shortened))",
            createdAt: date
        )
        try save(recording)
        return recording
    }

    /// Newest first. Folders without readable metadata are skipped.
    public func recordings() -> [Recording] {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        return folders
            .compactMap { try? load(id: $0.lastPathComponent) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Accepts a recording id or `"latest"`.
    public func recording(id: String) throws -> Recording {
        if id == Self.latestAlias {
            guard let latest = recordings().first else { throw LibraryError.empty }
            return latest
        }
        return try load(id: id)
    }

    public func save(_ recording: Recording) throws {
        try Self.encoder.encode(recording)
            .write(to: folder(for: recording.id).appendingPathComponent("meta.json"), options: .atomic)
    }

    public func transcript(for id: String) throws -> Transcript? {
        try Self.validate(id)
        let url = folder(for: id).appendingPathComponent("transcript.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Self.decoder.decode(Transcript.self, from: Data(contentsOf: url))
    }

    public func saveTranscript(_ transcript: Transcript, for id: String) throws {
        try Self.validate(id)
        try Self.encoder.encode(transcript)
            .write(to: folder(for: id).appendingPathComponent("transcript.json"), options: .atomic)
    }

    private func load(id: String) throws -> Recording {
        try Self.validate(id)
        let url = folder(for: id).appendingPathComponent("meta.json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw LibraryError.notFound(id) }
        return try Self.decoder.decode(Recording.self, from: Data(contentsOf: url))
    }

    /// Ids arrive from MCP clients, so keep them from escaping the library folder.
    private static func validate(_ id: String) throws {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard !id.isEmpty, id.unicodeScalars.allSatisfy(allowed.contains) else {
            throw LibraryError.invalidID(id)
        }
    }

    private static let idFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
