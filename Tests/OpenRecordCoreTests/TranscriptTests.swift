import Foundation
@testable import OpenRecordCore
import OpenRecordTestSupport
import Testing

struct TranscriptTests {
    @Test(arguments: [(0.0, "0:00"), (59.9, "0:59"), (61, "1:01"), (3725, "1:02:05")])
    func formatsTimestamps(seconds: Double, expected: String) {
        #expect(formatTimestamp(seconds) == expected)
    }

    @Test func formatsOnlySegmentsOverlappingTheRange() {
        let transcript = Transcript(language: "en", segments: [
            .init(start: 0, end: 4, text: "Intro"),
            .init(start: 5, end: 9, text: "Middle"),
            .init(start: 70, end: 75, text: "End"),
        ])

        #expect(transcript.formatted() == "[0:00] Intro\n[0:05] Middle\n[1:10] End")
        #expect(transcript.formatted(from: 6, to: 60) == "[0:05] Middle")
    }

    @Test func parsesWhisperJSONAndDropsNonSpeechMarkers() throws {
        let json = """
            {"result": {"language": "tr"}, "transcription": [
              {"offsets": {"from": 3970, "to": 7280}, "text": " Merhaba dünya."},
              {"offsets": {"from": 7280, "to": 9000}, "text": " [BLANK_AUDIO]"},
              {"offsets": {"from": 9000, "to": 9500}, "text": " (music)"},
              {"offsets": {"from": 9500, "to": 9900}, "text": "   "}
            ]}
            """
        let transcript = try WhisperTranscriber.parse(whisperJSON: Data(json.utf8))

        #expect(transcript.language == "tr")
        #expect(transcript.segments == [.init(start: 3.97, end: 7.28, text: "Merhaba dünya.")])
    }

    @Test func parsesWhisperJSONWithInvalidUTF8() throws {
        var data = Data(#"{"transcription": [{"offsets": {"from": 0, "to": 1000}, "text": "ok "#.utf8)
        data.append(0xE2)
        data.append(contentsOf: Data(#""}]}"#.utf8))

        let transcript = try WhisperTranscriber.parse(whisperJSON: data)

        #expect(transcript.segments.count == 1)
        #expect(transcript.segments[0].text.hasPrefix("ok"))
    }
}
