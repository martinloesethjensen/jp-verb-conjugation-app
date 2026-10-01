import SwiftUI
import VerbKit

/// Every lesson that attaches to verbs, one row each, opening the lesson in the
/// Grammar tab. Driven by the lesson data, so lessons added later appear on
/// their own.
struct VerbLessonsPage: View {
    @Environment(VerbStore.self) private var verbStore
    @Environment(\.openRoute) private var openRoute

    private var lessons: [GrammarPoint] {
        verbStore.grammarPoints.attachingToVerbs
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(lessons.enumerated()), id: \.element.id) { index, lesson in
                    if index > 0 { Divider() }
                    Button {
                        openRoute(.grammar(lesson.id))
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            JapaneseText(lesson.title)
                                .font(.headline)
                            JapaneseText(lesson.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .formCard()
            .padding()
        }
        .navigationTitle(VerbSubPage.lessons.title)
    }
}
