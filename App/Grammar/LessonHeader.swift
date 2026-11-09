import SwiftUI
import VerbKit

/// The top of a lesson: levels, the course lesson, the review pill, the title in Mincho, keywords,
/// the summary, the formula card and, when the lesson has a quiz, Practise this pattern.
struct LessonHeader: View {
    let point: GrammarPoint
    let lesson: CourseLesson?
    let onPractise: (() -> Void)?

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                LevelBadge(range: point.levelRange, emphasis: .header)
                if point.usages.count > 1 {
                    Text("· \(point.usages.count) usages")
                        .font(.subheadline)
                        .foregroundStyle(palette.muted)
                }
            }
            if let lesson {
                HStack(spacing: 8) {
                    Text(lesson.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.ink)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .overlay(Capsule().stroke(palette.rule, lineWidth: 1))
                    if lesson.unreviewed {
                        Text("unreviewed").font(.caption2).foregroundStyle(palette.muted)
                    }
                }
            }
            ReviewStatusPill(
                item: "Lesson: \(point.title) (\(point.id))", review: point.review,
                checked: ["That every kanji has a reading", "That related lessons exist"],
                unchecked: ["The explanations and example sentences", "The attachment rules", "The pitfalls"])
            JapaneseText(point.title)
                .font(.headword(.largeTitle))
                .foregroundStyle(palette.ink)
                .accessibilityAddTraits(.isHeader)
            if !point.keywords.isEmpty {
                WrappingFlowLayout(spacing: 6) {
                    ForEach(point.keywords, id: \.self) { keyword in
                        JapaneseText(keyword)
                            .font(.footnote)
                            .foregroundStyle(palette.ink)
                            .padding(.horizontal, 10).padding(.vertical, 3)
                            .overlay(Capsule().stroke(palette.rule, lineWidth: 1))
                    }
                }
            }
            JapaneseText(point.summary)
                .font(.headline)
                .foregroundStyle(palette.muted)
            if let formula = point.formula {
                FormulaCard(point: point, formula: formula)
            }
            if let onPractise {
                Button(action: onPractise) {
                    Label("Practise this pattern", systemImage: "arrow.right")
                }
                .buttonStyle(.paper)
            }
        }
    }
}
