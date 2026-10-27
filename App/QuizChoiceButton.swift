import SwiftUI
import VerbKit

/// One answer of a quiz: a pastel button with a shape that turns green or red once
/// answered. Shared by the verb quiz and the connection quiz.
struct QuizChoiceButton: View {
    let choice: String
    let index: Int
    let isCorrect: Bool
    let isSelected: Bool
    let isAnswered: Bool
    /// Lines the choice may use; `nil` for choices that are whole phrases and must not be cut off.
    var lineLimit: Int? = 3
    let action: () -> Void

    static let correctColor = Color(red: 0.13, green: 0.55, blue: 0.32)
    static let wrongColor = Color(red: 0.78, green: 0.20, blue: 0.20)

    private static let shapeSymbols = ["triangle.fill", "diamond.fill", "circle.fill", "square.fill"]
    // Pastels from the app palette (labels are near-black, as on `accentPill`). The shapes carry
    // the identity; correct/wrong use deeper green and red so they stand out from every choice.
    private static let choiceColors: [Color] = [
        TeGroup.tte.accentColor,
        VerbType.ru.accentColor,
        VerbType.u.accentColor,
        TeGroup.ite.accentColor,
    ]

    var body: some View {
        var background = Self.choiceColors[index % Self.choiceColors.count]
        var labelColor = Color.black.opacity(0.85)
        if isAnswered {
            if isCorrect { background = Self.correctColor; labelColor = .white }
            else if isSelected { background = Self.wrongColor; labelColor = .white }
        }
        return Button(action: action) {
            HStack {
                Image(systemName: Self.shapeSymbols[index % Self.shapeSymbols.count])
                Text(choice)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                    .lineLimit(lineLimit)
                if isAnswered && isCorrect { Image(systemName: "checkmark") }
                if isAnswered && isSelected && !isCorrect { Image(systemName: "xmark") }
            }
            .frame(maxWidth: .infinity, minHeight: 60)
            .foregroundStyle(labelColor)
        }
        .buttonStyle(.glassProminent)
        .accessibilityValue(statusDescription)
        .tint(background)
        .allowsHitTesting(!isAnswered)
        .opacity(isAnswered && !isCorrect && !isSelected ? 0.35 : 1)
    }

    /// What the check mark and cross say to VoiceOver, so the result is not only visual.
    private var statusDescription: String {
        guard isAnswered else { return "" }
        if isCorrect { return isSelected ? "Your answer, correct" : "Correct answer" }
        return isSelected ? "Your answer, wrong" : ""
    }
}
