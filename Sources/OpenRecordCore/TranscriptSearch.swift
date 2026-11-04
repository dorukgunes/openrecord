import Foundation

public struct SearchHit: Sendable, Codable, Equatable {
    public var recordingID: String
    public var recordingTitle: String
    public var start: Double
    public var text: String
}

public enum TranscriptSearch {
    /// Case- and accent-insensitive; a hit needs every query word within one segment or two adjacent ones.
    /// Results are newest recording first, then in playback order.
    public static func search(_ query: String, in library: RecordingLibrary, limit: Int = 20) -> [SearchHit] {
        let terms = normalize(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return [] }

        func containsAll(_ segments: ArraySlice<Transcript.Segment>) -> Bool {
            let haystack = normalize(segments.map(\.text).joined(separator: " "))
            return terms.allSatisfy { haystack.contains($0) }
        }

        var hits: [SearchHit] = []
        for recording in library.recordings() {
            guard let segments = try? library.transcript(for: recording.id)?.segments else { continue }
            var index = 0
            while index < segments.count, hits.count < limit {
                let next = index + 1
                let matched: ArraySlice<Transcript.Segment>
                if containsAll(segments[index...index]) {
                    matched = segments[index...index]
                } else if next < segments.count, !containsAll(segments[next...next]), containsAll(segments[index...next]) {
                    matched = segments[index...next]
                } else {
                    index += 1
                    continue
                }
                hits.append(SearchHit(
                    recordingID: recording.id,
                    recordingTitle: recording.title,
                    start: matched.first!.start,
                    text: matched.map(\.text).joined(separator: " ")
                ))
                index += matched.count
            }
            if hits.count >= limit { break }
        }
        return hits
    }

    private static func normalize(_ text: String) -> String {
        // Turkish dotless ı is its own letter, not an accented i, so diacritic folding leaves it alone.
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "ı", with: "i")
    }
}
