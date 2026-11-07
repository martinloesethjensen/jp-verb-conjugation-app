public extension TextUnit {
    /// `units` with the characters in `characters` (offsets into the joined text) marked
    /// emphasised. A unit with a reading that the range only partly covers is emphasised whole,
    /// so a kanji and its furigana never split. A plain unit the range partly covers splits at
    /// the range's edges; the pieces after the first glue to the one before, so they never wrap
    /// apart. The range is clamped to the text; an empty range changes nothing.
    static func emphasizing(_ units: [TextUnit], characters: Range<Int>) -> [TextUnit] {
        let total = units.reduce(0) { $0 + $1.text.count }
        let lower = min(max(characters.lowerBound, 0), total)
        let upper = min(max(characters.upperBound, lower), total)
        guard lower < upper else { return units }

        var result: [TextUnit] = []
        var offset = 0
        for unit in units {
            let start = offset
            let end = offset + unit.text.count
            offset = end
            let overlapStart = max(start, lower)
            let overlapEnd = min(end, upper)
            guard overlapStart < overlapEnd else {
                result.append(unit)
                continue
            }
            if unit.reading != nil || (overlapStart == start && overlapEnd == end) {
                var whole = unit
                whole.isEmphasized = true
                result.append(whole)
                continue
            }
            let chars = Array(unit.text)
            let pieces: [(Range<Int>, Bool)] = [
                (0..<(overlapStart - start), false),
                ((overlapStart - start)..<(overlapEnd - start), true),
                ((overlapEnd - start)..<chars.count, false),
            ]
            var first = true
            for (range, emphasized) in pieces where !range.isEmpty {
                result.append(TextUnit(
                    text: String(chars[range]),
                    glueToPrevious: first ? unit.glueToPrevious : true,
                    isEmphasized: emphasized
                ))
                first = false
            }
        }
        return result
    }
}
