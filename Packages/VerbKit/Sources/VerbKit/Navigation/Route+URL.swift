import Foundation

public extension Route {
    /// The custom URL scheme the app registers; widgets use it to open a verb.
    static let urlScheme = "verbtable"

    /// `verbtable://verb/<id>` or `verbtable://grammar/<id>`, with the id percent-encoded.
    var url: URL {
        var components = URLComponents()
        components.scheme = Self.urlScheme
        switch self {
        case let .verb(id):
            components.host = "verb"
            components.percentEncodedPath = "/" + Self.encode(id)
        case let .grammar(id):
            components.host = "grammar"
            components.percentEncodedPath = "/" + Self.encode(id)
        }
        return components.url!
    }

    /// nil for anything that is not one of this app's links.
    init?(url: URL) {
        guard url.scheme == Self.urlScheme, let host = url.host else { return nil }
        let path = url.path   // already percent-decoded
        guard path.hasPrefix("/"), path.count > 1 else { return nil }
        let id = String(path.dropFirst())
        switch host {
        case "verb": self = .verb(id)
        case "grammar": self = .grammar(id)
        default: return nil
        }
    }

    private static func encode(_ id: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id
    }
}
