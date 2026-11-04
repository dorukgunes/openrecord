import Foundation
import OpenRecordCore
import OpenRecordTestSupport
import Testing

struct TranscriptionQueueTests {
    let library: RecordingLibrary

    init() throws {
        library = RecordingLibrary(root: try Fixtures.temporaryDirectory())
    }

    @Test func keepsRecordingPendingWhenWhisperIsMissing() async throws {
        let recording = try Fixtures.addRecording(to: library, createdAt: .now)
        let queue = TranscriptionQueue(library: library, makeTranscriber: { throw TranscriptionError.whisperNotInstalled })

        await queue.enqueue(recording.id)
        await queue.waitUntilIdle()

        let saved = try library.recording(id: recording.id)
        #expect(saved.transcriptStatus == .pending)
        #expect(saved.transcriptError?.contains("whisper-cli not found") == true)
    }

    @Test func enqueueUnfinishedSkipsFinishedAndFailedRecordings() async throws {
        let pending = try Fixtures.addRecording(to: library, createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        var failed = try Fixtures.addRecording(to: library, createdAt: Date(timeIntervalSince1970: 1_700_000_100))
        failed.transcriptStatus = .failed
        try library.save(failed)
        try Fixtures.addRecording(
            to: library,
            createdAt: Date(timeIntervalSince1970: 1_700_000_200),
            transcript: Transcript(language: "en", segments: [])
        )
        let attempted = Attempts()
        let queue = TranscriptionQueue(library: library, makeTranscriber: {
            attempted.record()
            throw TranscriptionError.whisperNotInstalled
        })

        await queue.enqueueUnfinished()
        await queue.waitUntilIdle()

        #expect(attempted.count == 1)
        #expect(try library.recording(id: pending.id).transcriptError != nil)
        #expect(try library.recording(id: failed.id).transcriptError == nil)
    }

    @Test(.enabled(if: Fixtures.whisperAvailable, "needs whisper-cli and the model from scripts/setup-whisper.sh"))
    func transcribesAndMarksTheRecordingDone() async throws {
        let dir = try Fixtures.temporaryDirectory()
        let speech = dir.appendingPathComponent("speech.aiff")
        let colors = dir.appendingPathComponent("colors.mp4")
        let video = dir.appendingPathComponent("video.mp4")
        try Fixtures.makeSpeech("The invoice total is wrong.", at: speech)
        try await Fixtures.makeColorVideo(at: colors, colors: Array(repeating: .green, count: 5))
        try await Fixtures.mux(video: colors, audio: speech, audioOffset: 1, to: video)
        let recording = try Fixtures.addRecording(to: library, createdAt: .now, video: video)
        let queue = TranscriptionQueue(library: library)

        await queue.enqueue(recording.id)
        await queue.waitUntilIdle()

        let saved = try library.recording(id: recording.id)
        #expect(saved.transcriptStatus == .done)
        #expect(saved.transcriptLanguage == "en")
        #expect(try library.transcript(for: recording.id)?.text.lowercased().contains("invoice") == true)
    }
}

private final class Attempts: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func record() { lock.withLock { value += 1 } }
}
