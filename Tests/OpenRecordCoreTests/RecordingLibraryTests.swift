import Foundation
import OpenRecordCore
import OpenRecordTestSupport
import Testing

struct RecordingLibraryTests {
    let library: RecordingLibrary

    init() throws {
        library = RecordingLibrary(root: try Fixtures.temporaryDirectory())
    }

    @Test func createsUniqueIDsForRecordingsInTheSameSecond() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try library.createRecording(at: date)
        let second = try library.createRecording(at: date)

        #expect(first.id != second.id)
        #expect(second.id == "\(first.id)-2")
        #expect(FileManager.default.fileExists(atPath: library.folder(for: second.id).appendingPathComponent("meta.json").path))
    }

    @Test func listsNewestFirstAndResolvesLatest() throws {
        let old = try library.createRecording(at: Date(timeIntervalSince1970: 1_700_000_000))
        let new = try library.createRecording(at: Date(timeIntervalSince1970: 1_800_000_000))

        #expect(library.recordings().map(\.id) == [new.id, old.id])
        #expect(try library.recording(id: "latest").id == new.id)
    }

    @Test func latestOnEmptyLibraryThrows() {
        #expect(throws: LibraryError.empty) { try library.recording(id: "latest") }
    }

    @Test(arguments: ["../secrets", "a/b", "", "..", "x y"])
    func rejectsIDsThatCouldEscapeTheLibrary(id: String) {
        #expect(throws: LibraryError.invalidID(id)) { try library.recording(id: id) }
    }

    @Test func roundTripsMetadataAndTranscript() throws {
        var recording = try library.createRecording()
        recording.status = .ready
        recording.duration = 12.5
        recording.transcriptStatus = .done
        try library.save(recording)
        let transcript = Transcript(language: "en", segments: [.init(start: 1, end: 2, text: "Hello")])
        try library.saveTranscript(transcript, for: recording.id)

        #expect(try library.recording(id: recording.id) == recording)
        #expect(try library.transcript(for: recording.id) == transcript)
    }

    @Test func skipsFoldersWithoutMetadata() throws {
        try FileManager.default.createDirectory(at: library.root.appendingPathComponent("stray"), withIntermediateDirectories: true)
        let recording = try library.createRecording()

        #expect(library.recordings().map(\.id) == [recording.id])
    }
}
