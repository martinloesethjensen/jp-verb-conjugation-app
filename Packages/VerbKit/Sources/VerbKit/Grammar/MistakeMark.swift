import Foundation

/// Which part of a wrong form is wrong, so only that part is marked red (学生[だ]かもしれない).
public enum MistakeMark {
    /// Aligns `wrong` with the best-matching stretch of `right`: as much of `wrong`'s start and end
    /// as appear there, at most three characters apart. The rest of `wrong` is the wrong part.
    /// When too little lines up (under two characters, or under a third of `wrong`), or nothing is
    /// left over, the whole of `wrong` is marked.
    public static func wrongRange(wrong: String, right: String?) -> Range<Int> {
        let w = Array(wrong)
        let whole = 0..<w.count
        guard let right, !w.isEmpty else { return whole }
        let r = Array(right)
        var best = (prefix: 0, suffix: 0)
        for start in 0...r.count {
            var p = 0
            while p < w.count, start + p < r.count, w[p] == r[start + p] { p += 1 }
            // The longest suffix of `wrong` that appears in `right` soon after the prefix.
            for s in stride(from: w.count - p, through: 0, by: -1) {
                guard s > 0 else { break }
                let suffix = Array(w[(w.count - s)...])
                let from = start + p
                let latest = min(r.count - s, from + 3)
                guard from <= latest else { continue }
                if (from...latest).contains(where: { Array(r[$0..<($0 + s)]) == suffix }) {
                    if p + s > best.prefix + best.suffix { best = (p, s) }
                    break
                }
            }
            if p > best.prefix + best.suffix { best = (p, 0) }
        }
        let matched = best.prefix + best.suffix
        guard matched >= 2, matched * 3 >= w.count, matched < w.count else { return whole }
        return best.prefix..<(w.count - best.suffix)
    }
}
