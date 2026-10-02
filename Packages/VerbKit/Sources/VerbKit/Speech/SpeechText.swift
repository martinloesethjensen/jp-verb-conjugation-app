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

    /// The file name (without extension) of the recorded clip for already-cleaned
    /// text: the first 16 hex digits of its UTF-8 SHA-256. `scripts/generate_audio.py`
    /// computes the same name, so a clip is found by its text and a text with no clip
    /// falls back to the system voice.
    public static func clipName(for spoken: String) -> String {
        String(sha256Hex(of: Data(spoken.utf8)).prefix(16))
    }
}
