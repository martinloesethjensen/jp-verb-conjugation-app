import Foundation

/// One kanji from `data/kanji.json`: its strokes as SVG path data in KanjiVG's 109 × 109 box (y down),
/// in stroke order, and its KANJIDIC2 readings, meanings and school grade.
/// Contract: `docs/superpowers/specs/2026-11-07-kanji-stroke-order-design.md`.
public struct KanjiEntry: Equatable, Sendable {
    public var character: Character
    /// One SVG path `d` per stroke, in stroke order.
    public var strokes: [String]
    /// School grade 1–6, or 8 for the jōyō kanji taught in secondary school; nil otherwise.
    public var grade: Int?
    /// On readings, in katakana.
    public var on: [String]
    /// Kun readings in KANJIDIC2 notation (`た.べる`, `-かた`); `KanjiReading.display` formats them.
    public var kun: [String]
    /// English meanings, at most three.
    public var meanings: [String]

    public init(character: Character, strokes: [String], grade: Int? = nil, on: [String] = [], kun: [String] = [],
                meanings: [String] = []) {
        self.character = character
        self.strokes = strokes
        self.grade = grade
        self.on = on
        self.kun = kun
        self.meanings = meanings
    }
}
