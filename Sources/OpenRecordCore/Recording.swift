import Foundation

public struct Recording: Codable, Sendable, Equatable, Identifiable {
    public enum Status: String, Codable, Sendable {
        case recording
        case ready
        case failed
    }

    public enum TranscriptStatus: String, Codable, Sendable {
        case pending
        case transcribing
        case done
        case failed
        case noAudio = "no_audio"
    }

    public var id: String
    public var title: String
    public var createdAt: Date
    public var status: Status
    public var videoFile: String
    public var duration: Double?
    public var width: Int?
    public var height: Int?
    public var displayName: String?
    public var microphone: String?
    public var error: String?
    public var transcriptStatus: TranscriptStatus
    public var transcriptLanguage: String?
    public var transcriptError: String?

    public init(
        id: String,
        title: String,
        createdAt: Date,
        status: Status = .recording,
        videoFile: String = "recording.mp4",
        transcriptStatus: TranscriptStatus = .pending
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.status = status
        self.videoFile = videoFile
        self.transcriptStatus = transcriptStatus
    }
}
