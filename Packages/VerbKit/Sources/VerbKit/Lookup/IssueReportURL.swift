import Foundation

/// Links to the GitHub issue form for reporting a problem with a verb, a lesson or
/// the app. The form's fields are prefilled through the query string, so the
/// reporter only describes what is wrong.
public enum IssueReportURL {
    public static let repository = "martinloesethjensen/jp-verb-conjugation-app"

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    private static func encoded(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    /// The report form, with the item (e.g. "Verb: たべる (食べる)") and the versions
    /// line prefilled. A blank item leaves that field empty for the reporter to fill.
    public static func report(item: String, versions: String) -> URL {
        let item = item.trimmingCharacters(in: .whitespacesAndNewlines)
        var query = [
            "template=report-issue.yml",
            "labels=report",
            "title=" + encoded(item.isEmpty ? "[REPORT]" : "[REPORT] " + item),
        ]
        if !item.isEmpty { query.append("item=" + encoded(item)) }
        query.append("versions=" + encoded(versions))
        return URL(string: "https://github.com/\(repository)/issues/new?" + query.joined(separator: "&"))!
    }

    /// "app 0.1.0 (1) · verbs 1.3.0 · grammar 1.3.0 · furigana 1.2.0", with "unknown"
    /// for a data file that has not synced yet.
    public static func versions(app: String, verbs: String?, grammar: String?, furigana: String?) -> String {
        "app \(app) · verbs \(verbs ?? "unknown") · grammar \(grammar ?? "unknown") · furigana \(furigana ?? "unknown")"
    }
}
