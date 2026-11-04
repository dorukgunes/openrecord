import Foundation
import MCP
import OpenRecordCore
@testable import OpenRecordMCPServer
import OpenRecordTestSupport
import Testing

struct OpenRecordServerTests {
    @Test func listsAllToolsAsReadOnly() async throws {
        let (client, _) = try await connect(library: RecordingLibrary(root: try Fixtures.temporaryDirectory()))

        let (tools, _) = try await client.listTools()

        #expect(Set(tools.map(\.name)) == ["list_recordings", "get_recording", "get_transcript", "search_recordings", "get_frames"])
        #expect(tools.allSatisfy { $0.annotations.readOnlyHint == true })
    }

    @Test func listsRecordingsNewestFirstWithTranscriptPreview() async throws {
        let library = RecordingLibrary(root: try Fixtures.temporaryDirectory())
        let old = try Fixtures.addRecording(to: library, createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        let new = try Fixtures.addRecording(
            to: library,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            transcript: Transcript(language: "en", segments: [.init(start: 0, end: 2, text: "Hello there")])
        )
        let (client, _) = try await connect(library: library)

        let json = try await callJSON(client, "list_recordings", [:])

        let recordings = try #require(json["recordings"] as? [[String: Any]])
        #expect(recordings.map { $0["id"] as? String } == [new.id, old.id])
        #expect(recordings[0]["transcript_preview"] as? String == "Hello there")
        #expect(recordings[0]["duration"] as? String == "0:03")
    }

    @Test func returnsTimestampedTranscriptForLatest() async throws {
        let library = RecordingLibrary(root: try Fixtures.temporaryDirectory())
        try Fixtures.addRecording(to: library, createdAt: .now, transcript: Transcript(language: "en", segments: [
            .init(start: 1, end: 3, text: "First point."),
            .init(start: 65, end: 70, text: "Second point."),
        ]))
        let (client, _) = try await connect(library: library)

        let full = try await callText(client, "get_transcript", ["id": "latest"])
        let ranged = try await callText(client, "get_transcript", ["id": "latest", "start_seconds": 60])

        #expect(full.hasSuffix("[0:01] First point.\n[1:05] Second point."))
        #expect(ranged.hasSuffix("[1:05] Second point."))
        #expect(!ranged.contains("First point."))
    }

    @Test func explainsWhenTranscriptIsNotReady() async throws {
        let library = RecordingLibrary(root: try Fixtures.temporaryDirectory())
        let recording = try Fixtures.addRecording(to: library, createdAt: .now)
        let (client, _) = try await connect(library: library)

        let result = try await client.callTool(name: "get_transcript", arguments: ["id": .string(recording.id)])

        #expect(result.isError != true)
        #expect(text(of: result).contains("still being transcribed"))
    }

    @Test func searchesAcrossRecordings() async throws {
        let library = RecordingLibrary(root: try Fixtures.temporaryDirectory())
        let recording = try Fixtures.addRecording(to: library, createdAt: .now, transcript: Transcript(language: "en", segments: [
            .init(start: 42, end: 45, text: "The Stripe webhook times out."),
        ]))
        let (client, _) = try await connect(library: library)

        let json = try await callJSON(client, "search_recordings", ["query": "stripe WEBHOOK"])

        let matches = try #require(json["matches"] as? [[String: Any]])
        #expect(matches.count == 1)
        #expect(matches[0]["recording_id"] as? String == recording.id)
        #expect(matches[0]["at"] as? String == "0:42")
    }

    @Test func returnsJPEGFramesAtRequestedTimestamps() async throws {
        let library = RecordingLibrary(root: try Fixtures.temporaryDirectory())
        let video = try Fixtures.temporaryDirectory().appendingPathComponent("colors.mp4")
        try await Fixtures.makeColorVideo(at: video, colors: [.red, .green, .blue])
        let recording = try Fixtures.addRecording(to: library, createdAt: .now, video: video)
        let (client, _) = try await connect(library: library)

        let result = try await client.callTool(name: "get_frames", arguments: [
            "id": .string(recording.id), "timestamps": [0.5, 2.5],
        ])

        let images = result.content.compactMap { content -> Data? in
            guard case .image(let data, "image/jpeg", _, _) = content else { return nil }
            return Data(base64Encoded: data)
        }
        #expect(images.count == 2)
        #expect(images.compactMap(Fixtures.centerColor(ofImage:)).map { Fixtures.looksLike($0, .red) } == [true, false])
        #expect(Fixtures.looksLike(try #require(Fixtures.centerColor(ofImage: images[1])), .blue))
        #expect(text(of: result).contains("Frame at 0:00"))
    }

    @Test func defaultsToEvenlySpacedFrames() async throws {
        let library = RecordingLibrary(root: try Fixtures.temporaryDirectory())
        let video = try Fixtures.temporaryDirectory().appendingPathComponent("colors.mp4")
        try await Fixtures.makeColorVideo(at: video, colors: [.red, .green, .blue, .red])
        let recording = try Fixtures.addRecording(to: library, createdAt: .now, video: video)
        let (client, _) = try await connect(library: library)

        let result = try await client.callTool(name: "get_frames", arguments: ["id": .string(recording.id)])

        #expect(result.content.filter { if case .image = $0 { true } else { false } }.count == 4)
    }

    @Test func reportsBadIDsAsToolErrors() async throws {
        let library = RecordingLibrary(root: try Fixtures.temporaryDirectory())
        let (client, _) = try await connect(library: library)

        let traversal = try await client.callTool(name: "get_recording", arguments: ["id": "../../etc"])
        let missing = try await client.callTool(name: "get_recording", arguments: ["id": "2020-01-01_00-00-00"])
        let empty = try await client.callTool(name: "get_frames", arguments: ["id": "latest"])

        #expect(traversal.isError == true && text(of: traversal).contains("Invalid recording id"))
        #expect(missing.isError == true && text(of: missing).contains("No recording"))
        #expect(empty.isError == true && text(of: empty).contains("no recordings"))
    }

    @Test func getRecordingIncludesVideoPath() async throws {
        let library = RecordingLibrary(root: try Fixtures.temporaryDirectory())
        let recording = try Fixtures.addRecording(to: library, createdAt: .now)
        let (client, _) = try await connect(library: library)

        let json = try await callJSON(client, "get_recording", ["id": .string(recording.id)])

        #expect(json["video_path"] as? String == library.videoURL(for: recording).path)
        #expect(json["transcript_status"] as? String == "pending")
    }

    private func connect(library: RecordingLibrary) async throws -> (Client, Server) {
        let server = await OpenRecordServer.make(library: library)
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()
        try await server.start(transport: serverTransport)
        let client = Client(name: "openrecord-tests", version: "1.0")
        _ = try await client.connect(transport: clientTransport)
        return (client, server)
    }

    private func callText(_ client: Client, _ name: String, _ arguments: [String: Value]) async throws -> String {
        let result = try await client.callTool(name: name, arguments: arguments)
        #expect(result.isError != true, "\(name) failed: \(text(of: result))")
        return text(of: result)
    }

    private func callJSON(_ client: Client, _ name: String, _ arguments: [String: Value]) async throws -> [String: Any] {
        let string = try await callText(client, name, arguments)
        return try #require(try JSONSerialization.jsonObject(with: Data(string.utf8)) as? [String: Any])
    }

    private func text(of result: (content: [Tool.Content], isError: Bool?)) -> String {
        result.content.compactMap { if case .text(let text, _, _) = $0 { text } else { nil } }.joined(separator: "\n")
    }
}
