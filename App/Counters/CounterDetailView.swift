import SwiftUI
import VerbKit

/// A counter's page: the counter, how to count with it (Count them), every reading,
/// what it counts, examples, traps and related counters. `focus` rings one number in the readings.
struct CounterDetailView: View {
    let counter: Counter
    var focus: CounterNumber?
    @Environment(CountersStore.self) private var store
    @Environment(\.furiganaDictionary) private var furigana
    /// The number the playground shows; the readings grid rings the same one.
    @State private var number: CounterNumber

    init(counter: Counter, focus: CounterNumber? = nil) {
        self.counter = counter
        self.focus = focus
        _number = State(initialValue: focus ?? .n(1))
    }

    /// The groups this counter belongs to, in grid order.
    private var groups: [CounterGroup] {
        store.groups.filter { group in group.members.contains { $0.counter == counter.id } }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    countThemSection
                    readingsSection
                    if !counter.things.isEmpty { thingsSection }
                    if !counter.examples.isEmpty { examplesSection }
                    if !counter.pitfalls.isEmpty { pitfallsSection }
                    if !store.related(to: counter).isEmpty { relatedSection }
                }
                .padding()
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .onAppear {
                guard let focus else { return }
                DispatchQueue.main.async {
                    withAnimation { proxy.scrollTo(focus, anchor: .center) }
                }
            }
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

    private func sectionHeader(_ title: String, systemImage: String? = nil) -> some View {
        Label {
            Text(title)
        } icon: {
            if let systemImage { Image(systemName: systemImage) }
        }
        .font(.title3.weight(.semibold))
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
                Spacer(minLength: 0)
                Image(systemName: counter.symbol)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
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
            if !groups.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(groups) { group in
                            NavigationLink(value: CounterDestination.group(group)) {
                                Label(group.title, systemImage: group.symbol)
                            }
                            .buttonStyle(.glass)
                        }
                    }
                }
            }
        }
    }

    private var countThemSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Count them")
            CountThemCard(counter: counter, number: $number)
        }
    }

    private var readingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Readings")
            ReadingsGrid(counter: counter, focus: number)
        }
    }

    private var thingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("What it counts")
            ThingChips(counter: counter)
        }
    }

    private var examplesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Examples")
            card {
                ForEach(Array(counter.examples.enumerated()), id: \.offset) { index, example in
                    if index > 0 { Divider() }
                    CounterExampleRow(example: example, dictionary: furigana)
                }
            }
        }
    }

    private var pitfallsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Watch out", systemImage: "exclamationmark.triangle")
            ForEach(Array(counter.pitfalls.enumerated()), id: \.offset) { _, pitfall in
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

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Related")
            ForEach(store.related(to: counter)) { related in
                NavigationLink(value: CounterDestination.counter(related, focus: nil)) {
                    Label("\(related.counter)  \(related.meaning)", systemImage: "arrow.right.circle")
                }
                .buttonStyle(.glass)
            }
        }
    }
}

/// A counter example. Its own `readings` win over the furigana dictionary, so 一日 reads as the
/// example says (ついたち on the date page, いちにち on the days page).
struct CounterExampleRow: View {
    let example: CounterExample
    let dictionary: FuriganaDictionary?

    var body: some View {
        ExampleRow(example: GrammarExample(jp: example.jp, en: example.en))
            .environment(\.furiganaDictionary, dictionary.map { example.furigana(over: $0) })
    }
}
