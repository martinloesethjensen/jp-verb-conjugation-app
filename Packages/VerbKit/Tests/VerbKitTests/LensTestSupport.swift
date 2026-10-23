import XCTest
@testable import VerbKit

/// A tokenizer that returns tokens fixed in advance, so the matcher tests don't depend on
/// the OS tokenizer's version. Each sentence lists its tokens as surfaces with optional
/// readings, `"入れ/いれ ます"`, or as recorded in `lens-sentence-tokens.json`.
struct FixedTokenizer: Tokenizing {
    let tokens: [String: [(surface: String, reading: String?)]]

    init(_ tokens: [String: [(surface: String, reading: String?)]]) {
        self.tokens = tokens
    }

    /// From space-separated tokens, each `surface` or `surface/reading`; the text is the
    /// tokens joined.
    init(_ sentences: [String]) {
        var tokens: [String: [(surface: String, reading: String?)]] = [:]
        for sentence in sentences {
            let parts = sentence.split(separator: " ").map { part in
                let pieces = part.split(separator: "/", maxSplits: 1).map(String.init)
                return (surface: pieces[0], reading: pieces.count > 1 ? pieces[1] : nil)
            }
            tokens[parts.map(\.surface).joined()] = parts
        }
        self.init(tokens)
    }

    /// The tokens recorded from `CFStringTokenizer` for every golden sentence.
    static func recorded() throws -> FixedTokenizer {
        struct File: Decodable { var sentences: [String: [[String]]] }
        let url = try XCTUnwrap(Bundle.module.url(forResource: "lens-sentence-tokens", withExtension: "json"))
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        return FixedTokenizer(file.sentences.mapValues { tokens in
            tokens.map { (surface: $0[0], reading: $0.count > 1 && !$0[1].isEmpty ? $0[1] : nil) }
        })
    }

    /// Each token found in order in `text`; none when the text has no fixed tokens.
    func tokens(in text: String) -> [Token] {
        guard let fixed = tokens[text] else { return [] }
        var from = text.startIndex
        return fixed.compactMap { token in
            guard let range = text.range(of: token.surface, range: from..<text.endIndex) else { return nil }
            from = range.upperBound
            return Token(range: range, surface: token.surface, reading: token.reading)
        }
    }
}
