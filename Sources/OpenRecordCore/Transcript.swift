import Foundation

public struct Transcript: Codable, Sendable, Equatable {
    public struct Segment: Codable, Sendable, Equatable {
        /// Seconds from the start of the recording.
        public var start: Double
        public var end: Double
        public var text: String

        public init(start: Double, end: Double, text: String) {
            self.start = start
            self.end = end
            self.text = text
        }
    }

    public var language: String?
    public var segments: [Segment]

    public init(language: String?, segments: [Segment]) {
        self.language = language
        self.segments = segments
    }

    public var text: String {
        segments.map(\.text).joined(separator: " ")
    }

    /// One `[m:ss] text` line per segment overlapping the given range.
    public func formatted(from start: Double? = nil, to end: Double? = nil) -> String {
        segments
            .filter { segment in
                (start.map { segment.end >= $0 } ?? true) && (end.map { segment.start <= $0 } ?? true)
            }
            .map { "[\(formatTimestamp($0.start))] \($0.text)" }
            .joined(separator: "\n")
    }
}

public func formatTimestamp(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded(.down)))
    let (hours, minutes, secs) = (total / 3600, (total % 3600) / 60, total % 60)
    return hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, secs)
        : String(format: "%d:%02d", minutes, secs)
}
