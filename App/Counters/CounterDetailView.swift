import SwiftUI
import VerbKit

/// A counter's page: the counter and what it is, the pitfall in one line, the reading for the selected
/// number with a 1 to 10 strip and a stepper for numbers above 10 to change it, then Examples, Things and Related behind a control, and
/// Practise. `focus` selects a number (a Forms search result lands on it).
struct CounterDetailView: View {
    let counter: Counter
    var focus: CounterNumber?
    @Environment(CountersStore.self) private var store
    @Environment(\.furiganaDictionary) private var furigana
    @Environment(\.startCounterQuiz) private var startQuiz
    @AppStorage("quizQuestionCount", store: .appGroup) private var quizQuestionCount = 10
    @State private var number: CounterNumber
    @State private var segment: Segment = .examples
    @State private var showAllPitfalls = false

    private enum Segment: String, CaseIterable, Identifiable {
        case examples = "Examples", things = "Things", related = "Related"
        var id: String { rawValue }
    }

    init(counter: Counter, focus: CounterNumber? = nil) {
        self.counter = counter
        self.focus = focus
        _number = State(initialValue: focus ?? .n(1))
    }

    /// The home-list sections this counter is in, when there is something to compare it with.
    private var sections: [CounterSection] {
        store.sections.filter { $0.counters.contains(counter.id) && $0.counters.count > 1 }
    }

    private var segments: [Segment] {
        Segment.allCases.filter { segment in
            switch segment {
            case .examples: !counter.examples.isEmpty
            case .things: !counter.things.isEmpty
            case .related: !store.related(to: counter).isEmpty
            }
        }
    }

    private var shownSegment: Segment? { segments.contains(segment) ? segment : segments.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if !counter.pitfalls.isEmpty { pitfalls }
                ReadingBlock(counter: counter, number: number)
                NumberStrip(counter: counter, selection: $number)
                NumberStepper(counter: counter, selection: $number)
                if let shown = shownSegment { segmented(shown) }
                if !buildCounterQuestions(for: counter, count: 1).isEmpty { practise }
            }
            .padding()
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(counter.counter)
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                ReportProblemButton(item: "Counter: \(counter.counter) (\(counter.id))")
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(in: RoundedRectangle(cornerRadius: 10))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(counter.counter)
                    .font(.largeTitle.weight(.bold))
                Text(counter.reading)
                    .font(.title2)
                SpeakButton(text: counter.reading)
            }
            HStack(spacing: 8) {
                if let level = counter.jlpt {
                    Text(level.displayName)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .glassEffect(in: Capsule())
                }
                Text(counter.meaning)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            if !sections.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(sections) { section in
                            NavigationLink(value: CounterDestination.section(section)) {
                                Text(section.title)
                            }
                            .buttonStyle(.glass)
                        }
                    }
                }
            }
        }
    }

    /// The first pitfall in one line, with More for all of them (and their examples).
    @ViewBuilder private var pitfalls: some View {
        if showAllPitfalls {
            ForEach(Array(counter.pitfalls.enumerated()), id: \.offset) { _, pitfall in
                card {
                    JapaneseText(pitfall.heading).font(.headline)
                    if let wrong = pitfall.wrong { WrongForm(text: wrong) }
                    JapaneseText(pitfall.explanation).font(.subheadline)
                    ForEach(Array(pitfall.examples.enumerated()), id: \.offset) { _, example in
                        Divider()
                        CounterExampleRow(example: example, dictionary: furigana)
                    }
                }
            }
            Button("Less") { showAllPitfalls = false }
                .font(.subheadline)
        } else if let first = counter.pitfalls.first {
            let hint = pitfallHint(first)
            card {
                Label {
                    JapaneseText(hint.heading).font(.subheadline.weight(.semibold))
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                JapaneseText(hint.firstSentence).font(.subheadline)
                Button("More") { showAllPitfalls = true }
                    .font(.subheadline)
            }
        }
    }

    private func segmented(_ shown: Segment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if segments.count > 1 {
                Picker("Show", selection: Binding(get: { shown }, set: { segment = $0 })) {
                    ForEach(segments) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            switch shown {
            case .examples:
                card {
                    ForEach(Array(counter.examples.enumerated()), id: \.offset) { index, example in
                        if index > 0 { Divider() }
                        CounterExampleRow(example: example, dictionary: furigana)
                    }
                }
            case .things:
                ThingChips(counter: counter)
            case .related:
                ForEach(store.related(to: counter)) { related in
                    NavigationLink(value: CounterDestination.counter(related, focus: nil)) {
                        Label("\(related.counter)  \(related.meaning)", systemImage: "arrow.right.circle")
                    }
                    .buttonStyle(.glass)
                }
            }
        }
    }

    /// A read-it quiz about this counter alone.
    private var practise: some View {
        Button {
            startQuiz(buildCounterQuestions(for: counter, count: quizQuestionCount))
        } label: {
            Label("Practise this counter", systemImage: "graduationcap")
        }
        .buttonStyle(.glass)
    }
}

/// A counter example. Its own `readings` win over the furigana dictionary, so 一日 reads as the
/// example says (ついたち on the date page, いちにち on the days page).
struct CounterExampleRow: View {
    let example: CounterExample
    let dictionary: FuriganaDictionary?

    /// An example with its own readings is spoken from its kana, so the voice cannot read 一日 the
    /// wrong way. Others are spoken as written.
    private var speech: String? {
        guard !example.readings.isEmpty else { return nil }
        return (dictionary ?? .empty).merging(example.readings).reading(of: example.jp)
    }

    var body: some View {
        ExampleRow(example: GrammarExample(jp: example.jp, en: example.en), speech: speech)
            .environment(\.furiganaDictionary, dictionary.map { example.furigana(over: $0) })
    }
}
