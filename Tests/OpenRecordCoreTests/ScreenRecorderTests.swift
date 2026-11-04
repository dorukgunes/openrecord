import AVFoundation
import Foundation
import OpenRecordCore
import OpenRecordTestSupport
import Testing

/// Records the real screen, so it needs Screen Recording permission (and Microphone for the mic test).
/// Run with `OPENRECORD_CAPTURE_TESTS=1 swift test --filter ScreenRecorderTests`.
@Suite(
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["OPENRECORD_CAPTURE_TESTS"] == "1", "set OPENRECORD_CAPTURE_TESTS=1")
)
@MainActor
struct ScreenRecorderTests {
    @Test func recordsTheMainDisplayToAPlayableMP4() async throws {
        let (url, display) = try await record(seconds: 3, microphone: false)

        let asset = AVURLAsset(url: url)
        let video = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let size = try await video.load(.naturalSize)
        let duration = try await asset.load(.duration).seconds
        #expect(Int(size.width) == display.pixelWidth && Int(size.height) == display.pixelHeight)
        #expect(duration > 2 && duration < 5, "duration \(duration)")
        #expect(try await asset.loadTracks(withMediaType: .audio).isEmpty)
        #expect(try await FrameExtractor.frames(from: url, at: [1]).first?.jpeg.isEmpty == false)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["OPENRECORD_CAPTURE_MIC"] == "1", "set OPENRECORD_CAPTURE_MIC=1"))
    func recordsTheMicrophoneIntoTheSameFile() async throws {
        let (url, _) = try await record(seconds: 3, microphone: true)

        let audio = try await AVURLAsset(url: url).loadTracks(withMediaType: .audio)
        #expect(audio.count >= 1)
    }

    @Test func refusesToStartTwice() async throws {
        let recorder = ScreenRecorder()
        let display = try #require(ScreenRecorder.availableDisplays().first)
        let dir = try Fixtures.temporaryDirectory()
        _ = try await recorder.start(display: display.id, to: dir.appendingPathComponent("a.mp4"), captureMicrophone: false)

        await #expect(throws: RecorderError.self) {
            try await recorder.start(display: display.id, to: dir.appendingPathComponent("b.mp4"), captureMicrophone: false)
        }
        try await recorder.stop()
        await #expect(throws: RecorderError.self) { try await recorder.stop() }
    }

    private func record(seconds: Double, microphone: Bool) async throws -> (URL, DisplayOption) {
        let display = try #require(ScreenRecorder.availableDisplays().first)
        let url = try Fixtures.temporaryDirectory().appendingPathComponent("recording.mp4")
        let recorder = ScreenRecorder()

        _ = try await recorder.start(display: display.id, to: url, captureMicrophone: microphone)
        try await Task.sleep(for: .seconds(seconds))
        try await recorder.stop()

        #expect(FileManager.default.fileExists(atPath: url.path))
        return (url, display)
    }
}
