import Foundation

/// A pitfall boiled down for the counter page: its heading and the first sentence of its explanation.
public func pitfallHint(_ pitfall: CounterPitfall) -> (heading: String, firstSentence: String) {
    let text = pitfall.explanation.trimmingCharacters(in: .whitespacesAndNewlines)
    var end = text.endIndex
    if let stop = text.firstIndex(of: "。") {
        end = text.index(after: stop)
    }
    if let stop = text.range(of: ". "), stop.lowerBound < end {
        end = text.index(after: stop.lowerBound)
    }
    return (pitfall.heading, String(text[..<end]))
}
