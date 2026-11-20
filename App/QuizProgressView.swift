import Charts
import SwiftUI
import VerbKit

/// The Progress sheet: streaks, totals, the last 7 days and the weakest verbs, forms and counters,
/// all derived from the quiz history each time it renders.
struct QuizProgressView: View {
    @Environment(\.palette) private var palette
    @Environment(QuizHistoryStore.self) private var quizHistory
    @Environment(VerbStore.self) private var verbStore
    @Environment(CountersStore.self) private var countersStore
    @Environment(\.dismiss) private var dismiss
    @State private var showGuide = false

    var body: some View {
        let progress = QuizProgress(attempts: quizHistory.attempts)
        NavigationStack {
            Group {
                if progress.hasHistory {
                    content(progress)
                } else {
                    PaperEmptyState("No quiz history yet", message: "Your streak, accuracy and weak spots appear here once you answer quiz questions.")
                }
            }
            .paperBackground()
            .navigationTitle("Progress")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showGuide) { VerbGuideSheet() }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #endif
    }

    private func content(_ progress: QuizProgress) -> some View {
        Form {
            if let confusion = progress.confusion {
                Section {
                    ConfusionLine(confusion: confusion) { showGuide = true }
                }
                .paperRow()
            }
            Section("Streak") {
                LabeledContent("Current", value: days(progress.currentStreak))
                LabeledContent("Best", value: days(progress.bestStreak))
            }
            .paperRow()
            Section("Overall") {
                LabeledContent("Answered", value: "\(progress.totalAnswered)")
                LabeledContent("Accuracy", value: progress.accuracy.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
            }
            .paperRow()
            Section("Last 7 days") {
                Chart(progress.last7Days, id: \.day) { item in
                    BarMark(
                        x: .value("Day", item.day, unit: .day),
                        y: .value("Answered", item.answered)
                    )
                    .annotation(position: .top) {
                        if item.answered > 0 {
                            Text("\(item.answered)").font(.caption2).foregroundStyle(palette.muted)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisValueLabel(centered: true) {
                            if let date = value.as(Date.self) {
                                Text(date.formatted(.dateTime.weekday(.abbreviated)))
                            }
                        }
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 140)
                .padding(.vertical, 4)
            }
            .paperRow()
            if !progress.weakestVerbs.isEmpty {
                Section("Weakest verbs") {
                    let top = progress.weakestVerbs.map(\.weakness).max() ?? 1
                    ForEach(progress.weakestVerbs, id: \.verb) { weak in
                        HStack {
                            VStack(alignment: .leading) {
                                // The stored name is a `Verb.id`; show the verb's kana, not `きる:切る`.
                                Text(verb(withID: weak.verb)?.dict ?? weak.verb).font(.body)
                                if let kanji = kanji(forID: weak.verb) {
                                    JapaneseText(kanji).font(.caption).foregroundStyle(palette.muted)
                                }
                            }
                            Spacer()
                            WeaknessBar(value: weak.weakness / top)
                        }
                    }
                }
                .paperRow()
            }
            if !progress.weakestCounters.isEmpty {
                Section("Weakest counters") {
                    let top = progress.weakestCounters.map(\.weakness).max() ?? 1
                    ForEach(progress.weakestCounters, id: \.counterID) { weak in
                        HStack {
                            // A counter id the store no longer has shows as its id, never a crash.
                            if let counter = countersStore.counter(id: weak.counterID) {
                                VStack(alignment: .leading) {
                                    JapaneseText(units: counter.headwordUnits).font(.headword(.title3))
                                    Text("\(counter.reading) · \(counter.meaning)").font(.caption).foregroundStyle(palette.muted)
                                }
                            } else {
                                Text(weak.counterID).font(.body)
                            }
                            Spacer()
                            WeaknessBar(value: weak.weakness / top)
                        }
                    }
                }
                .paperRow()
            }
            if !progress.weakestForms.isEmpty {
                Section("Weakest forms") {
                    let top = progress.weakestForms.map(\.weakness).max() ?? 1
                    ForEach(progress.weakestForms, id: \.formID) { weak in
                        HStack {
                            Text(weak.label)
                            Spacer()
                            WeaknessBar(value: weak.weakness / top)
                        }
                    }
                }
                .paperRow()
            }
        }
        .formStyle(.grouped)
    }

    private func days(_ count: Int) -> String { count == 1 ? "1 day" : "\(count) days" }

    private func verb(withID id: String) -> Verb? {
        verbStore.verbs.first { $0.id == id }
    }

    private func kanji(forID id: String) -> String? {
        guard let match = verb(withID: id), let kanji = match.kanji, !kanji.isEmpty, kanji != match.dict else { return nil }
        return kanji
    }
}

/// "You often confuse ru- and u-verbs": the dominant mistake in recent wrong answers, with a
/// link to the verb guide when it explains that mistake. Wraps at any Dynamic Type size.
private struct ConfusionLine: View {
    @Environment(\.palette) private var palette
    let confusion: QuizConfusion
    let openGuide: () -> Void

    private var detail: String {
        "\(confusion.count) of your last \(confusion.windowSize) wrong answers. \(confusion.category.advice)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(confusion.category.headline).font(.headline)
            } icon: {
                Image(systemName: "lightbulb").foregroundStyle(palette.ink)
            }
            Text(detail).font(.callout).foregroundStyle(palette.muted)
            if confusion.category.opensVerbGuide {
                Button("See the verb guide", systemImage: "book", action: openGuide)
                    .buttonStyle(.paperSecondaryInline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(confusion.category.headline). \(detail)")
    }
}

/// A small bar relative to the weakest entry in its list.
private struct WeaknessBar: View {
    @Environment(\.palette) private var palette
    let value: Double

    var body: some View {
        Capsule()
            .fill(.quaternary)
            .frame(width: 60, height: 6)
            .overlay(alignment: .leading) {
                Capsule().fill(palette.ink).frame(width: 60 * min(max(value, 0), 1))
            }
            .accessibilityLabel("Weakness")
            .accessibilityValue("\(Int((min(max(value, 0), 1) * 100).rounded())) percent of the weakest")
    }
}
