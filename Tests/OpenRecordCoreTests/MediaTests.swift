import AVFoundation
import Foundation
import OpenRecordCore
import OpenRecordTestSupport
import Testing

struct FrameExtractorTests {
    @Test func extractsTheFrameShownAtEachTimestamp() async throws {
        let video = try Fixtures.temporaryDirectory().appendingPathComponent("colors.mp4")
        try await Fixtures.makeColorVideo(at: video, colors: [.red, .green, .blue])

        let frames = try await FrameExtractor.frames(from: video, at: [0.5, 1.5, 2.5, 99])

        let colors = frames.compactMap { Fixtures.centerColor(ofImage: $0.jpeg) }
        #expect(colors.count == 4)
        #expect(Fixtures.looksLike(colors[0], .red))
        #expect(Fixtures.looksLike(colors[1], .green))
        #expect(Fixtures.looksLike(colors[2], .blue))
        #expect(Fixtures.looksLike(colors[3], .blue), "timestamps past the end clamp to the last frame")
        #expect(frames[0].width == 320 && frames[0].height == 180)
    }

    @Test func downscalesToMaxWidth() async throws {
        let video = try Fixtures.temporaryDirectory().appendingPathComponent("colors.mp4")
        try await Fixtures.makeColorVideo(at: video, colors: [.red], width: 640, height: 360)

        let frame = try #require(try await FrameExtractor.frames(from: video, at: [0.2], maxWidth: 320).first)

        #expect(frame.width == 320 && frame.height == 180)
    }

    @Test func spacesFramesEvenly() {
        #expect(FrameExtractor.evenlySpacedTimes(count: 4, duration: 8) == [1, 3, 5, 7])
        #expect(FrameExtractor.evenlySpacedTimes(count: 3, duration: 0) == [0])
    }
}

@Suite(.enabled(if: Fixtures.whisperAvailable, "needs whisper-cli and the model from scripts/setup-whisper.sh"))
struct WhisperTranscriberTests {
    @Test func transcribesSpeechInsideAVideoWithCorrectTimestamps() async throws {
        let dir = try Fixtures.temporaryDirectory()
        let speech = dir.appendingPathComponent("speech.aiff")
        let colors = dir.appendingPathComponent("colors.mp4")
        let recording = dir.appendingPathComponent("recording.mp4")
        try Fixtures.makeSpeech("The checkout page crashes when I apply the discount code.", at: speech)
        try await Fixtures.makeColorVideo(at: colors, colors: Array(repeating: .blue, count: 8))
        try await Fixtures.mux(video: colors, audio: speech, audioOffset: 2, to: recording)

        let transcript = try #require(try await WhisperTranscriber.locate().transcribe(mediaURL: recording))

        let text = transcript.text.lowercased()
        #expect(text.contains("checkout"))
        #expect(text.contains("discount code"))
        #expect(transcript.language == "en")
        let start = try #require(transcript.segments.first?.start)
        #expect(abs(start - 2) < 0.8, "speech starts 2s in, got \(start)")
    }

    @Test func returnsNilForVideoWithoutAudio() async throws {
        let video = try Fixtures.temporaryDirectory().appendingPathComponent("silent.mp4")
        try await Fixtures.makeColorVideo(at: video, colors: [.red])

        #expect(try await WhisperTranscriber.locate().transcribe(mediaURL: video) == nil)
    }
}
