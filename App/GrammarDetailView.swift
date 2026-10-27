import SwiftUI
import VerbKit

struct GrammarDetailView: View {
    let point: GrammarPoint
    @Environment(VerbStore.self) private var verbStore
    @Environment(\.openRoute) private var openRoute
    @Environment(WordsStore.self) private var wordsStore
    @Environment(QuizHistoryStore.self) private var quizHistory
    @AppStorage("quizQuestionCount", store: .appGroup) private var quizQuestionCount = 10
    @State private var connectionQuestions: [ConnectionQuestion]?

    @Environment(CourseStore.self) private var courseStore

    private var lessonTag: CourseLesson? {
        courseStore.course?.lessonTag(for: point.id, points: verbStore.grammarPoints, textbooks: verbStore.textbooks)
    }

    private let registerOrder: [GrammarRegister] = [.polite, .casual, .formal]

    /// Related points that exist locally; a link to a lesson that hasn't
    /// synced is hidden rather than dead.
    private var relatedPoints: [GrammarPoint] {
        point.related.compactMap { id in
            if case let .grammar(related)? = Route.grammar(id).resolve(verbs: [], grammarPoints: verbStore.grammarPoints) {
                return related
            }
            return nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if !point.attachment.isEmpty { AttachmentSection(rules: point.attachment) }
                usagesSection
                if !point.contrasts.isEmpty { contrastsSection }
                if !point.conjugations.isEmpty { conjugationsSection }
                if !point.pitfalls.isEmpty { pitfallsSection }
                if point.hasConnections { practiseSection }
                if !relatedPoints.isEmpty { relatedSection }
            }
            .padding()
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        #if os(iOS)
        .fullScreenCover(isPresented: connectionBinding) {
            if let connectionQuestions {
                ConnectionQuizView(questions: connectionQuestions, recorder: { quizHistory.record($0) },
                                   onDone: { self.connectionQuestions = nil })
            }
        }
        #else
        .sheet(isPresented: connectionBinding) {
            if let connectionQuestions {
                ConnectionQuizView(questions: connectionQuestions, recorder: { quizHistory.record($0) },
                                   onDone: { self.connectionQuestions = nil })
                    .frame(minWidth: 560, minHeight: 640)
            }
        }
        #endif
        .navigationTitle(point.title)
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                ReportProblemButton(item: "Lesson: \(point.title) (\(point.id))")
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            LevelBadge(level: point.jlpt, emphasis: .header)
            if let lesson = lessonTag {
                HStack(spacing: 8) {
                    Text(lesson.name)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .glassEffect(in: Capsule())
                    if lesson.unreviewed {
                        Text("unreviewed").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            JapaneseText(point.title)
                .font(.largeTitle.weight(.heavy))
            JapaneseText(point.summary)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .glassCard()
    }

    // MARK: Don't confuse with

    private var contrastsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Don't confuse with", systemImage: "arrow.left.arrow.right")
            ForEach(Array(point.contrasts.enumerated()), id: \.offset) { _, contrast in
                card {
                    JapaneseText(contrast.pattern).font(.headline)
                    JapaneseText(contrast.explanation).font(.subheadline)
                    ForEach(Array(contrast.examples.enumerated()), id: \.offset) { _, example in
                        Divider()
                        ExampleRow(example: example)
                    }
                }
            }
        }
    }

    // MARK: Usages

    private var usagesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Usages")
            ForEach(Array(point.usages.enumerated()), id: \.offset) { index, usage in
                card {
                    JapaneseText("\(index + 1). \(usage.heading)").font(.headline)
                    JapaneseText(usage.explanation).font(.subheadline)
                    ForEach(Array(usage.examples.enumerated()), id: \.offset) { _, example in
                        Divider()
                        ExampleRow(example: example)
                    }
                }
            }
        }
    }

    // MARK: Conjugations

    private var conjugationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Conjugations")
            ForEach(registerOrder, id: \.self) { register in
                let forms = point.conjugations.filter { $0.register == register }
                if !forms.isEmpty {
                    card {
                        Text(register.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(Array(forms.enumerated()), id: \.offset) { _, conjugation in
                            VStack(alignment: .leading, spacing: 2) {
                                JapaneseText(conjugation.form).font(.headline)
                                if let note = conjugation.note {
                                    JapaneseText(note).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Practise

    private var practiseSection: some View {
        Button {
            let levels = LevelSettings.load()
            let verbs = verbStore.verbs.visible(in: levels)
            let questions = buildConnectionQuestions(points: [point], verbs: verbs, words: wordsStore.words.visible(in: levels), count: quizQuestionCount)
            if !questions.isEmpty { connectionQuestions = questions }
        } label: {
            Label("Practise this pattern", systemImage: "arrow.right")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
    }

    private var connectionBinding: Binding<Bool> {
        Binding(
            get: { connectionQuestions != nil },
            set: { if !$0 { connectionQuestions = nil } }
        )
    }

    // MARK: Watch out

    private var pitfallsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Watch out", systemImage: "exclamationmark.triangle")
            ForEach(Array(point.pitfalls.enumerated()), id: \.offset) { _, pitfall in
                card {
                    JapaneseText(pitfall.heading).font(.headline)
                    JapaneseText(pitfall.explanation).font(.subheadline)
                    ForEach(Array(pitfall.examples.enumerated()), id: \.offset) { _, example in
                        Divider()
                        ExampleRow(example: example)
                    }
                }
            }
        }
    }

    // MARK: Related

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Related")
            ForEach(relatedPoints) { related in
                Button {
                    openRoute(.grammar(related.id))
                } label: {
                    Label {
                        JapaneseText(related.title)
                    } icon: {
                        Image(systemName: "arrow.right.circle")
                    }
                }
                .buttonStyle(.glass)
            }
        }
    }
}
