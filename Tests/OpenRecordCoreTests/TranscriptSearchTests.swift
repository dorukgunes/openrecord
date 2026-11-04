import Foundation
import OpenRecordCore
import OpenRecordTestSupport
import Testing

struct TranscriptSearchTests {
    let library: RecordingLibrary
    let older: Recording
    let newer: Recording

    init() throws {
        library = RecordingLibrary(root: try Fixtures.temporaryDirectory())
        older = try Fixtures.addRecording(
            to: library,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            transcript: Transcript(language: "en", segments: [
                .init(start: 2, end: 5, text: "The invoice total is wrong"),
                .init(start: 6, end: 9, text: "after applying a discount code."),
            ])
        )
        newer = try Fixtures.addRecording(
            to: library,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            transcript: Transcript(language: "tr", segments: [
                .init(start: 1, end: 3, text: "Fatura TOPLAMI yanlış görünüyor."),
                .init(start: 10, end: 12, text: "Unrelated sentence about the invoice."),
            ])
        )
    }

    @Test func matchesAllWordsIgnoringCaseAndAccents() {
        let hits = TranscriptSearch.search("toplami yanlis", in: library)

        #expect(hits.map(\.recordingID) == [newer.id])
        #expect(hits.first?.start == 1)
    }

    @Test func matchesAcrossAdjacentSegments() {
        let hits = TranscriptSearch.search("wrong discount", in: library)

        #expect(hits.count == 1)
        #expect(hits.first?.start == 2)
        #expect(hits.first?.text == "The invoice total is wrong after applying a discount code.")
    }

    @Test func prefersTheSingleSegmentThatContainsEveryWord() {
        let hits = TranscriptSearch.search("applying discount", in: library)

        #expect(hits.map(\.start) == [6])
        #expect(hits.first?.text == "after applying a discount code.")
    }

    @Test func returnsNewestRecordingFirstAndRespectsLimit() {
        #expect(TranscriptSearch.search("invoice", in: library).map(\.recordingID) == [newer.id, older.id])
        #expect(TranscriptSearch.search("invoice", in: library, limit: 1).count == 1)
    }

    @Test func blankQueryFindsNothing() {
        #expect(TranscriptSearch.search("   ", in: library).isEmpty)
    }
}
