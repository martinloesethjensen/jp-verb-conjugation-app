import Foundation

/// Where a counted number sits in a counter's example sentence, so the page can underline it: a number
/// (digits, full-width digits or kanji numerals, or 何) joined to the counter, or one of the counter's
/// kana readings for 1 to 10 and 何. A bare counter (本 in 本を読む) is not a count.
public enum CounterHighlight {
    private static let numerals = Set("0123456789０１２３４５６７８９一二三四五六七八九十百千万何")

    /// A character range over the first counted number, the longest when two start together; nil when
    /// the sentence has none.
    public static func range(in sentence: String, counter: Counter) -> Range<Int>? {
        let chars = Array(sentence)
        let mark = Array(counter.counter)
        // Kana readings of three or more characters: shorter ones (とお) are ordinary words too.
        let readings = Set(CounterNumber.allCases.flatMap { counter.readings(for: $0) })
            .map(Array.init)
            .filter { $0.count >= 3 }
        var best: Range<Int>?
        for start in chars.indices {
            if let found = best, found.lowerBound < start { break }
            var end = start
            while end < chars.count, numerals.contains(chars[end]) { end += 1 }
            if end > start, end + mark.count <= chars.count, Array(chars[end..<(end + mark.count)]) == mark {
                best = longer(best, start..<(end + mark.count))
            }
            for reading in readings where start + reading.count <= chars.count
                && Array(chars[start..<(start + reading.count)]) == reading {
                best = longer(best, start..<(start + reading.count))
            }
        }
        return best
    }

    private static func longer(_ current: Range<Int>?, _ candidate: Range<Int>) -> Range<Int> {
        guard let current else { return candidate }
        return candidate.count > current.count ? candidate : current
    }
}
