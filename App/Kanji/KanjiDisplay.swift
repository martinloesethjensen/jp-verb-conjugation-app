import VerbKit

/// The kanji sheet's wording.
enum KanjiDisplay {
    static let credit = "Stroke data: KanjiVG, CC BY-SA 3.0 · Readings: KANJIDIC2, CC BY-SA 4.0"
    static let settingsCredit = "Kanji stroke order from KanjiVG (CC BY-SA 3.0); readings and meanings from KANJIDIC2 (EDRDG, CC BY-SA 4.0)."

    /// "9 strokes · Grade 2"; "Secondary school" for grade 8; strokes only without a grade.
    static func strokeSummary(_ entry: KanjiEntry) -> String {
        let count = entry.strokes.count
        let strokes = count == 1 ? "1 stroke" : "\(count) strokes"
        switch entry.grade {
        case let grade? where (1...6).contains(grade): return "\(strokes) · Grade \(grade)"
        case 8?: return "\(strokes) · Secondary school"
        default: return strokes
        }
    }

    static func directionPhrase(_ direction: StrokeDirection) -> String {
        switch direction {
        case .right: "goes left to right"
        case .downRight: "goes down to the right"
        case .down: "goes straight down"
        case .downLeft: "goes down to the left"
        case .left: "goes right to left"
        case .upLeft: "goes up to the left"
        case .up: "goes straight up"
        case .upRight: "goes up to the right"
        }
    }

    static func strokePosition(_ step: Int, of count: Int) -> String {
        "Stroke \(step) of \(count)"
    }

    static func traceHint(_ direction: StrokeDirection) -> String {
        "Start at the red dot. This stroke \(directionPhrase(direction))."
    }

    static func reversed(_ direction: StrokeDirection) -> String {
        "Other way round: this stroke \(directionPhrase(direction)). Try again."
    }

    static func wrongPlace(_ step: Int) -> String {
        "That is not stroke \(step). Start at the red dot."
    }

    static func finished(_ count: Int) -> String {
        count == 1 ? "The stroke is right." : "All \(count) strokes in order."
    }
}
