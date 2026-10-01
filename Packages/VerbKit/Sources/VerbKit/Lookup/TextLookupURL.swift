import Foundation

/// Web links for looking up or translating a piece of Japanese text. Every function
/// returns `nil` for blank text. The text is percent-encoded as UTF-8 with only
/// the RFC 3986 unreserved characters left as they are, so `/`, `?`, `#`, `&`, `%`
/// and spaces inside it can never change the shape of the URL.
public enum TextLookupURL {
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    private static func encoded(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.addingPercentEncoding(withAllowedCharacters: unreserved)
    }

    /// A Jisho search for `text`.
    public static func jisho(_ text: String) -> URL? {
        encoded(text).flatMap { URL(string: "https://jisho.org/search/" + $0) }
    }

    /// DeepL's translator, Japanese to English. The text rides in the fragment.
    /// DeepL splits the fragment at a `/` even when it is percent-encoded and drops
    /// everything after it, so a slash becomes the fullwidth `／`, which it keeps.
    public static func deepL(_ text: String) -> URL? {
        encoded(text.replacingOccurrences(of: "/", with: "／")).flatMap { URL(string: "https://www.deepl.com/translator#ja/en/" + $0) }
    }

    /// Google Translate, Japanese to English.
    public static func google(_ text: String) -> URL? {
        encoded(text).flatMap {
            URL(string: "https://translate.google.com/?sl=ja&tl=en&text=" + $0 + "&op=translate")
        }
    }
}
