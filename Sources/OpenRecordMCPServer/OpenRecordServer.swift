import Foundation
import MCP
import OpenRecordCore

public enum OpenRecordServer {
    public static let version = "0.1.0"

    static let instructions = """
        OpenRecord gives read-only access to the user's local screen recordings and what they said while recording. \
        Start with list_recordings (or pass id "latest"), read get_transcript to learn what was said and when, \
        then call get_frames at the transcript's timestamps to see what was on screen.
        """

    public static func make(library: RecordingLibrary = RecordingLibrary()) async -> Server {
        let server = Server(
            name: "openrecord",
            version: version,
            instructions: instructions,
            capabilities: .init(tools: .init(listChanged: false))
        )
        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: tools)
        }
        await server.withMethodHandler(CallTool.self) { params in
            do {
                return try await call(params.name, arguments: params.arguments ?? [:], library: library)
            } catch {
                return .init(content: [text(error.localizedDescription)], isError: true)
            }
        }
        return server
    }

    static let tools: [Tool] = [
        Tool(
            name: "list_recordings",
            description: "List screen recordings, newest first, with duration, transcript status and a preview of what was said.",
            inputSchema: schema([
                "limit": ["type": "integer", "minimum": 1, "maximum": 100, "description": "Maximum recordings to return (default 20)."],
            ]),
            annotations: readOnly("List recordings")
        ),
        Tool(
            name: "get_recording",
            description: "Metadata for one recording: title, date, duration, resolution, microphone, transcript status and the local video file path.",
            inputSchema: schema(["id": idProperty], required: ["id"]),
            annotations: readOnly("Get recording")
        ),
        Tool(
            name: "get_transcript",
            description: "What the user said in a recording, one `[m:ss] text` line per segment. Optionally limit to a time range.",
            inputSchema: schema([
                "id": idProperty,
                "start_seconds": ["type": "number", "minimum": 0, "description": "Only include speech at or after this time."],
                "end_seconds": ["type": "number", "minimum": 0, "description": "Only include speech at or before this time."],
            ], required: ["id"]),
            annotations: readOnly("Get transcript")
        ),
        Tool(
            name: "search_recordings",
            description: "Find moments across all recordings where the user said something. Matches every word, ignoring case and accents.",
            inputSchema: schema([
                "query": ["type": "string", "description": "Words to look for in transcripts."],
                "limit": ["type": "integer", "minimum": 1, "maximum": 100, "description": "Maximum matches (default 20)."],
            ], required: ["query"]),
            annotations: readOnly("Search recordings")
        ),
        Tool(
            name: "get_frames",
            description: "JPEG screenshots from a recording. Pass `timestamps` (seconds, e.g. from get_transcript) or `count` for evenly spaced frames.",
            inputSchema: schema([
                "id": idProperty,
                "timestamps": ["type": "array", "items": ["type": "number", "minimum": 0], "maxItems": .int(maxFrames), "description": "Seconds into the recording."],
                "count": ["type": "integer", "minimum": 1, "maximum": .int(maxFrames), "description": "Evenly spaced frames when no timestamps are given (default 4)."],
                "max_width": ["type": "integer", "minimum": 320, "maximum": 3840, "description": "Longest side in pixels (default 1280)."],
            ], required: ["id"]),
            annotations: readOnly("Get frames")
        ),
    ]

    static let maxFrames = 10

    static func call(_ name: String, arguments: [String: Value], library: RecordingLibrary) async throws -> CallTool.Result {
        switch name {
        case "list_recordings":
            let limit = arguments["limit"]?.intValue ?? 20
            let summaries = library.recordings().prefix(limit).map { summary(of: $0, library: library) }
            return json(["count": .int(summaries.count), "recordings": .array(Array(summaries))])

        case "get_recording":
            let recording = try library.recording(id: try requiredString("id", in: arguments))
            var details = summary(of: recording, library: library).objectValue ?? [:]
            details["video_path"] = .string(library.videoURL(for: recording).path)
            details["width"] = recording.width.map { .int($0) } ?? .null
            details["height"] = recording.height.map { .int($0) } ?? .null
            details["display"] = recording.displayName.map { .string($0) } ?? .null
            details["microphone"] = recording.microphone.map { .string($0) } ?? .null
            details["transcript_language"] = recording.transcriptLanguage.map { .string($0) } ?? .null
            details["transcript_error"] = recording.transcriptError.map { .string($0) } ?? .null
            details["error"] = recording.error.map { .string($0) } ?? .null
            return json(.object(details))

        case "get_transcript":
            let recording = try library.recording(id: try requiredString("id", in: arguments))
            guard recording.transcriptStatus == .done, let transcript = try library.transcript(for: recording.id) else {
                return .init(content: [text(transcriptUnavailableMessage(for: recording))], isError: recording.transcriptStatus == .failed)
            }
            let body = transcript.formatted(from: number(arguments["start_seconds"]), to: number(arguments["end_seconds"]))
            let header = "\(recording.title) (\(recording.id)), language: \(transcript.language ?? "unknown")"
            return .init(content: [text("\(header)\n\n\(body.isEmpty ? "(no speech in this range)" : body)")])

        case "search_recordings":
            let query = try requiredString("query", in: arguments)
            let hits = TranscriptSearch.search(query, in: library, limit: arguments["limit"]?.intValue ?? 20)
            let matches: [Value] = hits.map { hit in
                [
                    "recording_id": .string(hit.recordingID),
                    "recording_title": .string(hit.recordingTitle),
                    "at": .string(formatTimestamp(hit.start)),
                    "start_seconds": .double(hit.start),
                    "text": .string(hit.text),
                ]
            }
            return json(["query": .string(query), "count": .int(matches.count), "matches": .array(matches)])

        case "get_frames":
            let recording = try library.recording(id: try requiredString("id", in: arguments))
            let videoURL = library.videoURL(for: recording)
            let requested = (arguments["timestamps"]?.arrayValue ?? []).compactMap(number)
            let times = requested.isEmpty
                ? FrameExtractor.evenlySpacedTimes(
                    count: min(max(arguments["count"]?.intValue ?? 4, 1), maxFrames),
                    duration: try await FrameExtractor.duration(of: videoURL))
                : Array(requested.prefix(maxFrames))
            let frames = try await FrameExtractor.frames(
                from: videoURL, at: times, maxWidth: min(max(arguments["max_width"]?.intValue ?? 1280, 320), 3840)
            )
            var content: [Tool.Content] = []
            for frame in frames {
                content.append(text("Frame at \(formatTimestamp(frame.time)) (\(String(format: "%.1f", frame.time))s), \(frame.width)×\(frame.height)"))
                content.append(.image(data: frame.jpeg.base64EncodedString(), mimeType: "image/jpeg", annotations: nil, _meta: nil))
            }
            return .init(content: content)

        default:
            return .init(content: [text("Unknown tool: \(name)")], isError: true)
        }
    }

    private static func summary(of recording: Recording, library: RecordingLibrary) -> Value {
        var preview: Value = .null
        if recording.transcriptStatus == .done, let transcript = try? library.transcript(for: recording.id) {
            let text = transcript.text
            preview = .string(text.count > 200 ? String(text.prefix(200)) + "…" : text)
        }
        return [
            "id": .string(recording.id),
            "title": .string(recording.title),
            "created_at": .string(recording.createdAt.ISO8601Format()),
            "status": .string(recording.status.rawValue),
            "duration": recording.duration.map { .string(formatTimestamp($0)) } ?? .null,
            "duration_seconds": recording.duration.map { .double(($0 * 10).rounded() / 10) } ?? .null,
            "transcript_status": .string(recording.transcriptStatus.rawValue),
            "transcript_preview": preview,
        ]
    }

    private static func transcriptUnavailableMessage(for recording: Recording) -> String {
        switch recording.transcriptStatus {
        case .pending, .transcribing: "\(recording.id) is still being transcribed. Try again shortly."
        case .noAudio: "\(recording.id) has no audio, so there is no transcript."
        case .failed: "Transcription failed for \(recording.id): \(recording.transcriptError ?? "unknown error")"
        case .done: "The transcript file for \(recording.id) is missing."
        }
    }

    private static let idProperty: Value = [
        "type": "string",
        "description": "Recording id from list_recordings, or \"latest\" for the most recent recording.",
    ]

    private static func schema(_ properties: [String: Value], required: [String] = []) -> Value {
        ["type": "object", "properties": .object(properties), "required": .array(required.map { .string($0) })]
    }

    private static func readOnly(_ title: String) -> Tool.Annotations {
        .init(title: title, readOnlyHint: true, openWorldHint: false)
    }

    private static func requiredString(_ key: String, in arguments: [String: Value]) throws -> String {
        guard let value = arguments[key]?.stringValue?.trimmingCharacters(in: .whitespaces), !value.isEmpty else {
            throw MCPError.invalidParams("Missing required argument: \(key)")
        }
        return value
    }

    private static func number(_ value: Value?) -> Double? {
        value?.doubleValue ?? value?.intValue.map(Double.init)
    }

    private static func text(_ string: String) -> Tool.Content {
        .text(text: string, annotations: nil, _meta: nil)
    }

    private static func json(_ value: Value) -> CallTool.Result {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let string = (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return .init(content: [text(string)])
    }
}
