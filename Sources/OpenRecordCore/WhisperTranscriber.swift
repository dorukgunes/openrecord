import Foundation

public enum TranscriptionError: LocalizedError {
    case whisperNotInstalled
    case modelMissing(URL)
    case whisperFailed(status: Int32, output: String)

    public var errorDescription: String? {
        switch self {
        case .whisperNotInstalled:
            "whisper-cli not found. Run scripts/setup-whisper.sh (or `brew install whisper-cpp`)."
        case .modelMissing(let url):
            "Whisper model missing at \(url.path). Run scripts/setup-whisper.sh."
        case .whisperFailed(let status, let output):
            "whisper-cli exited with \(status): \(output.suffix(500))"
        }
    }
}

/// Transcribes by shelling out to whisper.cpp's `whisper-cli`.
public struct WhisperTranscriber: Sendable {
    public var cliURL: URL
    public var modelURL: URL
    public var vadModelURL: URL?

    public static let modelsFolder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/OpenRecord/models", isDirectory: true)

    public init(cliURL: URL, modelURL: URL, vadModelURL: URL?) {
        self.cliURL = cliURL
        self.modelURL = modelURL
        self.vadModelURL = vadModelURL
    }

    /// Finds whisper-cli and the models installed by scripts/setup-whisper.sh.
    /// `OPENRECORD_WHISPER_CLI` and `OPENRECORD_WHISPER_MODEL` override the defaults.
    public static func locate(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> WhisperTranscriber {
        // Apps launched from Finder get a bare PATH, so check Homebrew's prefixes explicitly.
        let pathDirs = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let candidates = [environment["OPENRECORD_WHISPER_CLI"]].compactMap { $0 }
            + (["/opt/homebrew/bin", "/usr/local/bin"] + pathDirs).map { "\($0)/whisper-cli" }
        guard let cli = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw TranscriptionError.whisperNotInstalled
        }

        let model = environment["OPENRECORD_WHISPER_MODEL"].map { URL(fileURLWithPath: $0) }
            ?? modelsFolder.appendingPathComponent("ggml-large-v3-turbo-q5_0.bin")
        guard FileManager.default.fileExists(atPath: model.path) else {
            throw TranscriptionError.modelMissing(model)
        }

        let vad = modelsFolder.appendingPathComponent("ggml-silero-v5.1.2.bin")
        return WhisperTranscriber(
            cliURL: URL(fileURLWithPath: cli),
            modelURL: model,
            vadModelURL: FileManager.default.fileExists(atPath: vad.path) ? vad : nil
        )
    }

    /// Returns nil when the media has no audio track.
    public func transcribe(mediaURL: URL) async throws -> Transcript? {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("openrecord-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let wav = workDir.appendingPathComponent("audio.wav")
        guard try await AudioExtractor.extractWAV(from: mediaURL, to: wav) else { return nil }

        let outputBase = workDir.appendingPathComponent("transcript")
        var arguments = [
            "-m", modelURL.path,
            "-f", wav.path,
            "-l", "auto",
            "-t", String(min(8, ProcessInfo.processInfo.activeProcessorCount)),
            "-sns",
            "-oj",
            "-of", outputBase.path,
            "-np",
        ]
        if let vadModelURL {
            arguments += ["--vad", "-vm", vadModelURL.path]
        }
        try await run(arguments: arguments, logURL: workDir.appendingPathComponent("whisper.log"))

        return try Self.parse(whisperJSON: Data(contentsOf: outputBase.appendingPathExtension("json")))
    }

    static func parse(whisperJSON data: Data) throws -> Transcript {
        struct Output: Decodable {
            struct Result: Decodable { var language: String? }
            struct Segment: Decodable {
                struct Offsets: Decodable { var from: Int; var to: Int }
                var offsets: Offsets
                var text: String
            }
            var result: Result?
            var transcription: [Segment]
        }
        // whisper.cpp can split a multi-byte character across tokens; decode leniently.
        let sanitized = Data(String(decoding: data, as: UTF8.self).utf8)
        let output = try JSONDecoder().decode(Output.self, from: sanitized)
        let segments = output.transcription.compactMap { segment -> Transcript.Segment? in
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !isNonSpeechMarker(text) else { return nil }
            return .init(start: Double(segment.offsets.from) / 1000, end: Double(segment.offsets.to) / 1000, text: text)
        }
        return Transcript(language: output.result?.language, segments: segments)
    }

    /// Whisper labels silence and noise as e.g. "[BLANK_AUDIO]" or "(music)".
    private static func isNonSpeechMarker(_ text: String) -> Bool {
        (text.hasPrefix("[") && text.hasSuffix("]")) || (text.hasPrefix("(") && text.hasSuffix(")"))
    }

    private func run(arguments: [String], logURL: URL) async throws {
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)
        defer { try? log.close() }

        let process = Process()
        process.executableURL = cliURL
        process.arguments = arguments
        process.standardOutput = log
        process.standardError = log

        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
        guard status == 0 else {
            let output = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            throw TranscriptionError.whisperFailed(status: status, output: output)
        }
    }
}
