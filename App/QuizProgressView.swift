import Charts
import SwiftUI
import VerbKit

/// The Progress sheet: streaks, totals, the last 7 days and the weakest verbs and forms,
/// all derived from the quiz history each time it renders.
struct QuizProgressView: View {
    @Environment(QuizHistoryStore.self) private var quizHistory
    @Environment(VerbStore.self) private var verbStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let progress = QuizProgress(attempts: quizHistory.attempts)
        NavigationStack {
            Group {
                if progress.hasHistory {
                    content(progress)
                } else {
                    ContentUnavailableView(
                        "No quiz history yet",
                        systemImage: "chart.bar",
                        description: Text("Your streak, accuracy and weak spots appear here once you answer quiz questions.")
                    )
                }
            }
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
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #endif
    }

    private func content(_ progress: QuizProgress) -> some View {
        Form {
            Section("Streak") {
                LabeledContent("Current", value: days(progress.currentStreak))
                LabeledContent("Best", value: days(progress.bestStreak))
            }
            Section("Overall") {
                LabeledContent("Answered", value: "\(progress.totalAnswered)")
                LabeledContent("Accuracy", value: progress.accuracy.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
            }
            Section("Last 7 days") {
                Chart(progress.last7Days, id: \.day) { item in
                    BarMark(
                        x: .value("Day", item.day, unit: .day),
                        y: .value("Answered", item.answered)
                    )
                    .annotation(position: .top) {
                        if item.answered > 0 {
                            Text("\(item.answered)").font(.caption2).foregroundStyle(.secondary)
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
            if !progress.weakestVerbs.isEmpty {
                Section("Weakest verbs") {
                    let top = progress.weakestVerbs.map(\.weakness).max() ?? 1
                    ForEach(progress.weakestVerbs, id: \.verb) { weak in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(weak.verb).font(.body)
                                if let kanji = kanji(for: weak.verb) {
                                    Text(kanji).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            WeaknessBar(value: weak.weakness / top)
                        }
                    }
                }
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
            }
        }
        .formStyle(.grouped)
    }

    private func days(_ count: Int) -> String { count == 1 ? "1 day" : "\(count) days" }

    private func kanji(for dict: String) -> String? {
        guard let kanji = verbStore.verbs.first(where: { $0.dict == dict })?.kanji, !kanji.isEmpty, kanji != dict else { return nil }
        return kanji
    }
}

/// A small bar relative to the weakest entry in its list.
private struct WeaknessBar: View {
    let value: Double

    var body: some View {
        Capsule()
            .fill(.quaternary)
            .frame(width: 60, height: 6)
            .overlay(alignment: .leading) {
                Capsule().fill(.orange).frame(width: 60 * min(max(value, 0), 1))
            }
            .accessibilityLabel("Weakness")
            .accessibilityValue("\(Int((min(max(value, 0), 1) * 100).rounded())) percent of the weakest")
    }
}
