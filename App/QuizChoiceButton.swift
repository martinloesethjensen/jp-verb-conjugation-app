import SwiftUI
import VerbKit

/// One answer of a quiz, marked like a teacher marks a paper once answered: the right answer gets
/// a green outline and a check, a wrong pick is struck through in the theme's red with a cross,
/// and the rest fade. Shared by the verb quiz and the connection quiz.
struct QuizChoiceButton: View {
    let choice: String
    let index: Int
    let isCorrect: Bool
    let isSelected: Bool
    let isAnswered: Bool
    /// Lines the choice may use; `nil` for choices that are whole phrases and must not be cut off.
    var lineLimit: Int? = 3
    let action: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityDifferentiateWithoutColor) private var withoutColor

    /// A small shape per position, so the four answers stay tellable apart without colour.
    private static let shapeSymbols = ["triangle.fill", "diamond.fill", "circle.fill", "square.fill"]

    private enum Mark { case none, correct, wrong, faded }

    private var mark: Mark {
        guard isAnswered else { return .none }
        if isCorrect { return .correct }
        return isSelected ? .wrong : .faded
    }

    private var fill: Color {
        switch mark {
        case .correct: palette.goodSoft
        case .wrong: palette.markSoft
        case .none, .faded: palette.card
        }
    }

    private var border: (Color, CGFloat) {
        switch mark {
        case .correct: (palette.good, 2)
        case .wrong: (palette.mark, 2)
        case .none, .faded: (palette.rule, 1)
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                HStack(spacing: 8) {
                    switch mark {
                    case .correct:
                        Image(systemName: "checkmark").foregroundStyle(palette.good)
                    case .wrong:
                        Image(systemName: "xmark").foregroundStyle(palette.mark)
                    case .none, .faded:
                        Image(systemName: Self.shapeSymbols[index % Self.shapeSymbols.count])
                            .font(.caption)
                            .foregroundStyle(palette.muted)
                    }
                    Text(choice)
                        .fontWeight(mark == .correct ? .bold : .regular)
                        .strikethrough(mark == .wrong, color: palette.mark)
                        // Ink text on the soft fills keeps 4.5:1; the strike, cross and outline carry the mark colour.
                        .foregroundStyle(palette.ink)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.8)
                        .lineLimit(lineLimit)
                }
                if withoutColor, let caption {
                    Text(caption)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(palette.ink)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(fill, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(border.0, lineWidth: border.1))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityValue(statusDescription)
        .allowsHitTesting(!isAnswered)
        .opacity(mark == .faded ? 0.45 : 1)
    }

    /// The words shown with Differentiate Without Color, so the mark never relies on colour.
    private var caption: String? {
        switch mark {
        case .correct: "Correct"
        case .wrong: "Your answer"
        case .none, .faded: nil
        }
    }

    /// What the check mark and cross say to VoiceOver, so the result is not only visual.
    private var statusDescription: String {
        guard isAnswered else { return "" }
        if isCorrect { return isSelected ? "Your answer, correct" : "Correct answer" }
        return isSelected ? "Your answer, wrong" : ""
    }
}
