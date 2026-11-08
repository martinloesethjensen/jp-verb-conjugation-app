import SwiftUI
import VerbKit

struct GrammarDetailView: View {
    let point: GrammarPoint
    /// A pitfall to scroll to and briefly highlight (Common mistakes sets it). Cleared once handled,
    /// so going back to the lesson later starts at the top again.
    @Binding var focusedPitfall: Int?
    @State private var highlightedPitfall: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.palette) private var palette
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

    init(point: GrammarPoint, focusedPitfall: Binding<Int?> = .constant(nil)) {
        self.point = point
        _focusedPitfall = focusedPitfall
    }

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
        ScrollViewReader { proxy in
            content
                .onChange(of: focusedPitfall, initial: true) { _, index in
                    guard let index else { return }
                    focusedPitfall = nil
                    guard point.pitfalls.indices.contains(index) else { return }
                    Task { await reveal(pitfall: index, with: proxy) }
                }
        }
    }

    private static func pitfallID(_ index: Int) -> String { "pitfall-\(index)" }

    /// Scrolls to a pitfall once the page has laid out, then rings it for a moment.
    private func reveal(pitfall index: Int, with proxy: ScrollViewProxy) async {
        try? await Task.sleep(for: .milliseconds(350))
        withAnimation(reduceMotion ? nil : .smooth) {
            proxy.scrollTo(Self.pitfallID(index), anchor: .top)
        }
        withAnimation(.easeIn(duration: 0.2)) { highlightedPitfall = index }
        try? await Task.sleep(for: .seconds(1.6))
        withAnimation(.easeOut(duration: 0.6)) { highlightedPitfall = nil }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                LessonHeader(point: point, lesson: lessonTag, onPractise: point.hasConnections ? practise : nil)
                if !point.attachment.isEmpty {
                    AttachmentSection(rules: point.attachment, patterns: GrammarHighlight.patterns(of: point))
                }
                LessonUsages(point: point)
                if !point.contrasts.isEmpty { contrastsSection }
                if !point.conjugations.isEmpty { FormsTable(conjugations: point.conjugations) }
                if !point.pitfalls.isEmpty { pitfallsSection }
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
        .paperBackground()
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

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .paperCard()
    }

    // MARK: Don't confuse with

    private var contrastsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Don't confuse with", systemImage: "arrow.left.arrow.right")
            ForEach(Array(point.contrasts.enumerated()), id: \.offset) { _, contrast in
                card {
                    JapaneseText(contrast.pattern).font(.headline)
                    JapaneseText(contrast.explanation).font(.subheadline)
                    if !contrast.examples.isEmpty {
                        ExampleList(examples: contrast.examples,
                                    patterns: [contrast.pattern] + GrammarHighlight.patterns(of: point))
                    }
                }
            }
        }
    }

    // MARK: Practise

    private func practise() {
        let levels = LevelSettings.load()
        let verbs = verbStore.verbs.visible(in: levels)
        let questions = buildConnectionQuestions(points: [point], verbs: verbs, words: wordsStore.words.visible(in: levels), count: quizQuestionCount)
        if !questions.isEmpty { connectionQuestions = questions }
    }

    private var connectionBinding: Binding<Bool> {
        Binding(
            get: { connectionQuestions != nil },
            set: { if !$0 { connectionQuestions = nil } }
        )
    }

    // MARK: Common mistakes

    private var pitfallsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Common mistakes")
            ForEach(Array(point.pitfalls.enumerated()), id: \.offset) { index, pitfall in
                card {
                    JapaneseText(pitfall.heading).font(.headline)
                    if let wrong = pitfall.wrong {
                        WrongForm(text: wrong, right: pitfall.examples.first?.jp)
                        if let right = pitfall.examples.first?.jp { RightForm(text: right) }
                    }
                    JapaneseText(pitfall.explanation).font(.subheadline)
                    let rest = pitfall.wrong == nil ? pitfall.examples : Array(pitfall.examples.dropFirst())
                    if !rest.isEmpty {
                        ExampleList(examples: rest, patterns: GrammarHighlight.patterns(of: point))
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(palette.button, lineWidth: 3)
                        .opacity(highlightedPitfall == index ? 1 : 0)
                        .allowsHitTesting(false)
                }
                .id(Self.pitfallID(index))
            }
        }
    }

    // MARK: Related

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Related")
            VStack(spacing: 0) {
                ForEach(Array(relatedPoints.enumerated()), id: \.element.id) { index, related in
                    if index > 0 { Divider().overlay(palette.rule) }
                    Button {
                        openRoute(.grammar(related.id))
                    } label: {
                        HStack(spacing: 10) {
                            GrammarRow(point: related)
                            Spacer(minLength: 0)
                            RowChevron()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .paperCard(cornerRadius: 14)
        }
    }
}
