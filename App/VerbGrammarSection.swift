import SwiftUI
import VerbKit

/// Every lesson that attaches to verbs, as links, at the bottom of a verb's
/// page. Driven by the lesson data, so lessons added later appear on their own;
/// hidden until grammar has synced.
struct VerbGrammarSection: View {
    @Environment(VerbStore.self) private var verbStore
    @Environment(\.openRoute) private var openRoute
    @State private var isExpanded = false

    private var lessons: [GrammarPoint] {
        verbStore.grammarPoints.attachingToVerbs
    }

    var body: some View {
        if !lessons.isEmpty {
            DisclosureGroup("Grammar", isExpanded: $isExpanded) {
                VStack(spacing: 8) {
                    ForEach(lessons) { lesson in
                        Button {
                            openRoute(.grammar(lesson.id))
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                JapaneseText(lesson.title)
                                    .font(.headline)
                                JapaneseText(lesson.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .glassEffect(in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
            }
            .font(.subheadline.weight(.semibold))
        }
    }
}
