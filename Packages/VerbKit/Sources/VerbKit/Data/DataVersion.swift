/// Orders the dotted numeric versions used in `manifest.json` ("1.4.0"), so the app
/// can refuse a manifest older than one it already accepted.
enum DataVersion {
    static func parse(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard let number = Int(part), number >= 0 else { return nil }
            numbers.append(number)
        }
        return numbers
    }

    /// True when `version` is older than `highest`. An unreadable version on either
    /// side counts as older, so garbage can never pass for a newer release.
    static func isOlder(_ version: String, than highest: String) -> Bool {
        guard let a = parse(version), let b = parse(highest) else { return true }
        let count = max(a.count, b.count)
        for i in 0..<count {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x < y }
        }
        return false
    }
}
