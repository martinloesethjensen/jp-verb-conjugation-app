import Foundation

/// What to say for a piece of on-screen Japanese text: trimmed, with the
/// separators "~" and "/" turned into nothing and a pause, and nil when there is
/// nothing left to say.
public enum SpeechText {
    public static func spoken(_ text: String) -> String? {
        var result = text
            .replacingOccurrences(of: "~", with: "")
            .replacingOccurrences(of: "〜", with: "")
        let pieces = result.split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        result = pieces.joined(separator: "、")
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
