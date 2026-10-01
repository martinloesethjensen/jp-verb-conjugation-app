import SwiftUI
import VerbKit

struct GrammarRow: View {
    let point: GrammarPoint

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                JapaneseText(point.title)
                    .font(.title3.weight(.bold))
                if let level = point.jlpt {
                    Text(level.displayName)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .glassEffect(in: Capsule())
                }
            }
            JapaneseText(point.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

struct GrammarListView: View {
    @Environment(VerbStore.self) private var verbStore
    @Binding var selection: GrammarPoint?
    @State private var search = ""
    @State private var scope: LevelScope = .mine
    @AppStorage(LevelSettings.defaultsKey, store: .appGroup) private var hiddenLevelsRaw = ""

    private var settings: LevelSettings { LevelSettings(rawValue: hiddenLevelsRaw) }
    private var availableLevels: Set<JLPTLevel> {
        verbStore.verbs.levels().union(verbStore.grammarPoints.levels())
    }
    private var levelsHidden: Bool { settings.anyHidden(among: availableLevels) }
    private var summary: String { settings.summary(among: availableLevels) ?? "" }

    private func matching(in levels: LevelSettings) -> [GrammarPoint] {
        verbStore.grammarPoints.visible(in: levels).filter { matchesGrammarSearch($0, query: search) }
    }

    private var filtered: [GrammarPoint] { matching(in: scope == .mine ? settings : LevelSettings()) }

    /// Matches hidden by the level setting, for the current search.
    private var hiddenMatchCount: Int {
        guard scope == .mine, levelsHidden, !search.isEmpty else { return 0 }
        return matching(in: LevelSettings()).count - filtered.count
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(filtered) { point in
                // Same row pattern as VerbListView: an explicit Button
                // sets the selection, and .tag keeps List's own selection
                // in sync (List(selection:) alone matches the row's id,
                // not the element, so taps would silently do nothing).
                Button {
                    selection = point
                } label: {
                    GrammarRow(point: point)
                }
                .buttonStyle(.plain)
                .tag(point)
            }
            if !filtered.isEmpty && hiddenMatchCount > 0 {
                HiddenMatchesRow(count: hiddenMatchCount) { scope = .all }
            }
        }
        .searchable(text: $search, prompt: "Search grammar…")
        .levelScopeBar(isActive: levelsHidden, scope: $scope)
        .onChange(of: search) { if search.isEmpty { scope = .mine } }
        .navigationTitle("Grammar")
        .navigationSubtitle(scope == .mine ? summary : "")
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                ReportProblemButton(item: "")
            }
        }
        .overlay {
            if !verbStore.hasGrammar {
                ContentUnavailableView {
                    Label("Grammar Not Downloaded Yet", systemImage: "icloud.and.arrow.down")
                } description: {
                    Text("Grammar lessons download in the background. Check your connection and try again.")
                } actions: {
                    Button("Try Again") {
                        Task { await verbStore.retryGrammarSync() }
                    }
                    .buttonStyle(.glassProminent)
                }
            } else if filtered.isEmpty {
                if hiddenMatchCount > 0 {
                    NoMatchInLevelsView(summary: summary, hiddenCount: hiddenMatchCount) { scope = .all }
                } else {
                    ContentUnavailableView.search(text: search)
                }
            }
        }
    }
}
