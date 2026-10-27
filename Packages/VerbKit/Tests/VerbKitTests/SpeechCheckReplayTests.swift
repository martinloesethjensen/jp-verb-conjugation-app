import XCTest
@testable import VerbKit

/// Not a test of its own: the speech check (`scripts/speech-check`, #143) scores transcripts with the
/// production `VerbMatcher`, so what it reports is what the Sentence lens would highlight. The harness
/// sets `SPEECH_CHECK_IN` to a JSON array of transcripts and `SPEECH_CHECK_OUT` to where the spans go;
/// without them this test is skipped.
final class SpeechCheckReplayTests: XCTestCase {
    private struct Hit: Encodable {
        var start: Int
        var surface: String
        var verbs: [String]
        var notInApp: Bool
    }

    func testReplayTranscripts() throws {
        let env = ProcessInfo.processInfo.environment
        guard let input = env["SPEECH_CHECK_IN"], let output = env["SPEECH_CHECK_OUT"] else {
            throw XCTSkip("Only runs under scripts/speech-check/speech_check.py")
        }
        let texts = try JSONDecoder().decode([String].self, from: Data(contentsOf: URL(fileURLWithPath: input)))
        let verbs = try RealVerbs.load()
        let index = FormIndex(verbs: verbs, catalogue: .bundled)
        let matcher = VerbMatcher(index: index, verbs: verbs)
        let results = texts.map { text in
            matcher.spans(in: text).map { span in
                Hit(start: text.distance(from: text.startIndex, to: span.range.lowerBound),
                    surface: span.surface, verbs: span.verbIDs, notInApp: span.status == .notInApp)
            }
        }
        try JSONEncoder().encode(results).write(to: URL(fileURLWithPath: output))
    }
}
