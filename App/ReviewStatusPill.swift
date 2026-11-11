import SwiftUI
import VerbKit

/// Whether the owner switched review markers on in Settings (on by default).
let showReviewStatusKey = "showReviewStatus"

/// A small capsule on a counter, grammar or verb page: "Not yet reviewed" (outlined in `muted`, with a question glyph; red is kept for mistakes) or "Reviewed" (a check).
/// Tapping opens a sheet that says what the data pipeline checks by itself and what nobody has checked yet.
struct ReviewStatusPill: View {
    /// What Report a problem names, "Counter: 本 (hon)".
    let item: String
    let review: ReviewStamp?
    /// What the pipeline verifies by itself for this kind of entry, and what no one has checked.
    let checked: [String]
    let unchecked: [String]
    /// A line shown under the headline whatever the state ("Example sentences are reviewed one by one…").
    var note: String? = nil
    @AppStorage(showReviewStatusKey, store: .appGroup) private var showReviewStatus = true
    @State private var showingSheet = false
    @Environment(\.palette) private var palette

    var body: some View {
        if showReviewStatus {
            Button {
                showingSheet = true
            } label: {
                Label(review == nil ? "Not yet reviewed" : "Reviewed",
                      systemImage: review == nil ? "questionmark.circle" : "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(review == nil ? palette.muted : palette.good)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(review == nil ? palette.muted : palette.good, lineWidth: 1))
                    .frame(minHeight: 44)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows what has been checked")
            .sheet(isPresented: $showingSheet) {
                ReviewStatusSheet(item: item, review: review, checked: checked, unchecked: unchecked, note: note)
            }
            .dismissOnLink { showingSheet = false }
        }
    }
}

private struct ReviewStatusSheet: View {
    @Environment(\.palette) private var palette
    let item: String
    let review: ReviewStamp?
    let checked: [String]
    let unchecked: [String]
    let note: String?
    @Environment(\.dismiss) private var dismiss

    private var headline: String {
        guard let review else { return "No one has reviewed this yet." }
        return "Reviewed by \(review.by.displayName) on \(review.on)."
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(headline)
                    if review != nil {
                        Text("The text has not changed since then. If it is edited, it goes back to not yet reviewed.")
                            .font(.footnote)
                            .foregroundStyle(palette.muted)
                    }
                    if let note {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(palette.muted)
                    }
                }
                .paperRow()
                Section("Checked automatically") {
                    ForEach(checked, id: \.self) { Label($0, systemImage: "checkmark") }
                }
                .paperRow()
                if review == nil {
                    Section("Not checked by a person yet") {
                        ForEach(unchecked, id: \.self) { Label($0, systemImage: "questionmark") }
                    }
                    .paperRow()
                }
                Section {
                    ReportProblemButton(item: item)
                }
                .paperRow()
            }
            .paperBackground()
            .navigationTitle("Review status")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// One quiet line under a list: "12 of 30 counters reviewed", or "No counters reviewed yet".
struct ReviewSummaryLine: View {
    @Environment(\.palette) private var palette
    let noun: String
    let summary: ReviewSummary
    @AppStorage(showReviewStatusKey, store: .appGroup) private var showReviewStatus = true

    var body: some View {
        if showReviewStatus && summary.total > 0 {
            Text(summary.reviewed == 0
                 ? "No \(noun) reviewed yet"
                 : "\(summary.reviewed) of \(summary.total) \(noun) reviewed")
                .font(.footnote)
                .foregroundStyle(palette.muted)
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowSeparator(.hidden)
        }
    }
}

/// Settings' Content review section: how much is reviewed, when, and the switch.
struct ContentReviewSection: View {
    @Environment(\.palette) private var palette
    @Environment(CountersStore.self) private var counters
    @Environment(VerbStore.self) private var verbs
    @Environment(WordsStore.self) private var words
    @AppStorage(showReviewStatusKey, store: .appGroup) private var showReviewStatus = true

    private func row(_ title: String, _ summary: ReviewSummary) -> some View {
        HStack {
            Text(title)
            Spacer()
            VStack(alignment: .trailing) {
                Text("\(summary.reviewed) of \(summary.total) reviewed")
                if let latest = summary.latest {
                    Text("Latest \(latest)").font(.caption).foregroundStyle(palette.muted)
                }
            }
            .foregroundStyle(palette.muted)
        }
        .accessibilityElement(children: .combine)
    }

    var body: some View {
        Section {
            row("Counters", ReviewSummary(counters.counters))
            row("Grammar", ReviewSummary(verbs.grammarPoints))
            row("Verbs", ReviewSummary(verbs.verbs))
            row("Example sentences", ReviewSummary(verbs.verbs.flatMap(\.examples)))
            row("Words", ReviewSummary(words.words))
            Toggle("Show review status", isOn: $showReviewStatus)
                .paperSwitch()
        } header: {
            Text("Content review")
        } footer: {
            Text("Readings, sound changes and conjugated forms are checked automatically. Meanings, examples, pitfalls and questions are marked once a person has read them.")
        }
        .paperRow()
    }
}
