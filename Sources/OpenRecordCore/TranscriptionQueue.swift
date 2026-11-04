import Foundation

/// Transcribes finished recordings one at a time and records progress in each recording's metadata.
public actor TranscriptionQueue {
    private let library: RecordingLibrary
    private let makeTranscriber: @Sendable () throws -> WhisperTranscriber
    private var queued: [String] = []
    private var inFlight: String?
    private var worker: Task<Void, Never>?
    private let onChange: @Sendable () -> Void

    public init(
        library: RecordingLibrary,
        makeTranscriber: @escaping @Sendable () throws -> WhisperTranscriber = { try WhisperTranscriber.locate() },
        onChange: @escaping @Sendable () -> Void = {}
    ) {
        self.library = library
        self.makeTranscriber = makeTranscriber
        self.onChange = onChange
    }

    public func enqueue(_ id: String) {
        guard !queued.contains(id), inFlight != id else { return }
        queued.append(id)
        guard worker == nil else { return }
        worker = Task { await drain() }
    }

    /// Picks up recordings left untranscribed: the app quit mid-transcription, or whisper wasn't installed yet.
    public func enqueueUnfinished() {
        for recording in library.recordings().reversed()
        where recording.status == .ready && [.pending, .transcribing].contains(recording.transcriptStatus) {
            enqueue(recording.id)
        }
    }

    public func waitUntilIdle() async {
        await worker?.value
    }

    private func drain() async {
        while !queued.isEmpty {
            let id = queued.removeFirst()
            inFlight = id
            await transcribe(id)
            inFlight = nil
        }
        worker = nil
    }

    private func transcribe(_ id: String) async {
        guard var recording = try? library.recording(id: id) else { return }
        let transcriber: WhisperTranscriber
        do {
            transcriber = try makeTranscriber()
        } catch {
            // Missing setup isn't this recording's fault: keep it pending so it's retried once whisper is installed.
            recording.transcriptStatus = .pending
            recording.transcriptError = error.localizedDescription
            try? library.save(recording)
            onChange()
            return
        }

        recording.transcriptStatus = .transcribing
        recording.transcriptError = nil
        try? library.save(recording)
        onChange()

        do {
            if let transcript = try await transcriber.transcribe(mediaURL: library.videoURL(for: recording)) {
                try library.saveTranscript(transcript, for: id)
                recording.transcriptStatus = .done
                recording.transcriptLanguage = transcript.language
            } else {
                recording.transcriptStatus = .noAudio
            }
        } catch {
            recording.transcriptStatus = .failed
            recording.transcriptError = error.localizedDescription
        }
        try? library.save(recording)
        onChange()
    }
}
