import SwiftUI
import VerbKit

/// "Learn about …" buttons for the given lessons, in the given order. A lesson
/// that has not synced yet shows no button, so a link never dead-ends.
struct LessonLinks: View {
    let ids: [String]
    @Environment(VerbStore.self) private var verbStore
    @Environment(\.openRoute) private var openRoute

    private var lessons: [GrammarPoint] {
        ids.compactMap { id in
            verbStore.grammarPoints.first { $0.id == id }
        }
    }

    var body: some View {
        ForEach(lessons) { lesson in
            Button {
                openRoute(.grammar(lesson.id))
            } label: {
                Label {
                    JapaneseText("Learn about \(lesson.title)")
                } icon: {
                    Image(systemName: "arrow.right.circle")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.glass)
            .font(.subheadline)
        }
    }
}
