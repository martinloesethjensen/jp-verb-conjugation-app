import SwiftUI
import VerbKit

/// What the counter quiz sheet reports.
enum CounterQuizSelection {
    case whichCounter, readIt, askIt, mixed, weakSpots
}

/// Asks what to practise before a counter quiz starts. A row is disabled when it would build no
/// question under the current level settings; Weak spots comes first.
struct CounterQuizSheet: View {
    /// How many questions each row can build, and how many weak reading pairs there are.
    let whichCounterAvailable: Bool
    let readItAvailable: Bool
    let askItAvailable: Bool
    let weakSpotCount: Int
    var onStart: (CounterQuizSelection) -> Void
    var onCancel: () -> Void

    @State private var choice: CounterQuizSelection = .mixed

    private var mixedAvailable: Bool { whichCounterAvailable || readItAvailable || askItAvailable }

    private func isAvailable(_ value: CounterQuizSelection) -> Bool {
        switch value {
        case .weakSpots: weakSpotCount > 0
        case .whichCounter: whichCounterAvailable
        case .readIt: readItAvailable
        case .askIt: askItAvailable
        case .mixed: mixedAvailable
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Practise") {
                    row("Weak spots", detail: weakSpotsDetail, value: .weakSpots)
                    row("Which counter?", detail: "Pick 本 for 傘", value: .whichCounter)
                    row("Read it", detail: "三本 is さんぼん", value: .readIt)
                    row("Ask it", detail: "何人 for \"How many people?\"", value: .askIt)
                    row("Mixed", detail: "All three", value: .mixed)
                }
            }
            .navigationTitle("Counter quiz")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { onStart(choice) }
                        .disabled(!isAvailable(choice))
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            if !isAvailable(choice) { choice = [.whichCounter, .readIt, .askIt].first(where: isAvailable) ?? .mixed }
        }
    }

    private var weakSpotsDetail: String {
        weakSpotCount > 0 ? "\(weakSpotCount) \(weakSpotCount == 1 ? "reading" : "readings")" : "Answer some questions first"
    }

    private func row(_ title: String, detail: String, value: CounterQuizSelection) -> some View {
        let enabled = isAvailable(value)
        return Button {
            choice = value
        } label: {
            HStack {
                Text(title).foregroundStyle(enabled ? .primary : .secondary)
                Spacer()
                Text(detail).foregroundStyle(.secondary)
                Image(systemName: choice == value ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(choice == value ? Color.accentColor : Color.secondary)
            }
            // On the label, so the gap between title and detail is tappable too.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
