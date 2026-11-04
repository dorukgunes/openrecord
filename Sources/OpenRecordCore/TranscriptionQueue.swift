import Foundation

/// Transcribes finished recordings one at a time and records progress in each recording's metadata.
public actor TranscriptionQueue {
    private let library: RecordingLibrary
    private let makeTranscriber: @Sendable () throws -> WhisperTranscriber
    private var queued: [String] = []
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
        guard !queued.contains(id) else { return }
        queued.append(id)
        guard worker == nil else { return }
        worker = Task { await drain() }
    }

    /// Picks up recordings left untranscribed, e.g. because the app quit mid-transcription.
    public func enqueueUnfinished() {
        for recording in library.recordings().reversed()
        where recording.status == .ready && [.pending, .transcribing].contains(recording.transcriptStatus) {
            enqueue(recording.id)
        }
    }

    private func drain() async {
        while !queued.isEmpty {
            await transcribe(queued.removeFirst())
        }
        worker = nil
    }

    private func transcribe(_ id: String) async {
        guard var recording = try? library.recording(id: id) else { return }
        recording.transcriptStatus = .transcribing
        recording.transcriptError = nil
        try? library.save(recording)
        onChange()

        do {
            let transcriber = try makeTranscriber()
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
