import SwiftUI
import VerbKit

/// The Counters sidebar: a grid of counting groups, or search results while a query is typed.
struct CountersHomeView: View {
    @Environment(CountersStore.self) private var store
    @Binding var destination: CounterDestination?
    @Binding var column: NavigationSplitViewColumn
    var onSettings: () -> Void
    var onQuiz: () -> Void
    @State private var search = ""
    @State private var scope: LevelScope = .mine
    @FocusState private var searchFocused: Bool
    @AppStorage(LevelSettings.defaultsKey, store: .appGroup) private var hiddenLevelsRaw = ""

    private var settings: LevelSettings { LevelSettings(rawValue: hiddenLevelsRaw) }
    private var availableLevels: Set<JLPTLevel> { store.counters.levels() }
    private var levelsHidden: Bool { settings.anyHidden(among: availableLevels) }
    private var summary: String { settings.summary(among: availableLevels) ?? "" }
    private var activeLevels: LevelSettings { scope == .mine ? settings : LevelSettings() }

    private func counters(in levels: LevelSettings) -> [Counter] {
        store.counters.visible(in: levels)
    }

    /// Groups with at least one counter left under `levels`.
    private func groups(in levels: LevelSettings) -> [CounterGroup] {
        let visible = counters(in: levels)
        return store.groups.filter { !$0.counters(in: visible).isEmpty }
    }

    private func results(in levels: LevelSettings) -> CounterSearchResults {
        searchCounters(counters(in: levels), groups: groups(in: levels), query: search)
    }

    private func rowCount(_ results: CounterSearchResults) -> Int {
        results.groups.count + results.counters.count + results.forms.count + results.things.count
    }

    private var hiddenMatchCount: Int {
        guard scope == .mine, levelsHidden, !search.isEmpty else { return 0 }
        return rowCount(results(in: LevelSettings())) - rowCount(results(in: settings))
    }

    private func go(_ next: CounterDestination) {
        destination = next
        column = .detail
    }

    var body: some View {
        content
            .navigationTitle("Counters")
            .navigationSubtitle(scope == .mine ? summary : "")
            .inlineSearch(text: $search, prompt: "Counters, 3本, sanbon, umbrella…", focused: $searchFocused)
            .levelScopeBar(isActive: levelsHidden, scope: $scope)
            .onChange(of: search) { if search.isEmpty { scope = .mine } }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Quiz", systemImage: "gamecontroller", action: onQuiz)
                        .disabled(store.counters.isEmpty)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu("More", systemImage: "ellipsis") {
                        Button("Settings", systemImage: "gearshape", action: onSettings)
                        ReportProblemButton(item: "")
                    }
                }
            }
    }

    @ViewBuilder private var content: some View {
        if store.counters.isEmpty {
            ContentUnavailableView {
                Label("Counters Not Downloaded Yet", systemImage: "icloud.and.arrow.down")
            } description: {
                Text("Counters download in the background. Check your connection, then reopen the app.")
            }
        } else if search.isEmpty {
            grid
        } else {
            CounterSearchResultsView(
                results: results(in: activeLevels), search: search, summary: summary,
                hiddenMatchCount: hiddenMatchCount, open: go
            )
        }
    }

    private var grid: some View {
        let visible = counters(in: settings)
        return ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach(groups(in: settings)) { group in
                    let members = group.counters(in: visible).map(\.counter.counter)
                    GroupTile(
                        title: group.title, symbol: group.symbol,
                        counters: members.joined(separator: " · "),
                        spokenCounters: members.joined(separator: ", ")
                    ) {
                        go(.group(group))
                    }
                }
                GroupTile(
                    title: "All counters", symbol: "list.bullet",
                    counters: "\(visible.count) counters", spokenCounters: "\(visible.count) counters"
                ) {
                    go(.all)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}
