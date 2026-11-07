/// Formats KANJIDIC2 kun readings for display: `た.べる` → `た(べる)` (okurigana in brackets), and the
/// `-` that marks a prefix or suffix use is dropped (`-かた` → `かた`). On readings need no change.
public enum KanjiReading {
    public static func display(_ kun: String) -> String {
        var reading = kun
        while reading.hasPrefix("-") { reading.removeFirst() }
        while reading.hasSuffix("-") { reading.removeLast() }
        guard let dot = reading.firstIndex(of: ".") else { return reading }
        return reading[..<dot] + "(" + reading[reading.index(after: dot)...] + ")"
    }
}
