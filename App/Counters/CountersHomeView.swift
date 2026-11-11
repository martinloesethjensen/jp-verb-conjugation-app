import SwiftUI
import VerbKit

/// The Counters sidebar: a search field and a directory of every counter under what it counts, or
/// search results while a query is typed.
struct CountersHomeView: View {
    @Environment(CountersStore.self) private var store
    @Binding var destination: CounterDestination?
    @Binding var column: NavigationSplitViewColumn
    var onSettings: () -> Void
    var onQuiz: () -> Void
    @State private var search = ""
    @State private var scope: LevelScope = .mine
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.palette) private var palette
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

    private var home: [CounterHomeSection] {
        homeSections(store.sections, counters: counters(in: settings))
    }

    private func go(_ next: CounterDestination) {
        destination = next
        column = .detail
    }

    var body: some View {
        content
            .paperBackground()
            .motifTitle("Counters")
            .navigationSubtitle(scope == .mine ? summary : "")
            .inlineSearch(
                text: $search, prompt: "Counters, 3本, sanbon, umbrella…", focused: $searchFocused
            )
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
            PaperEmptyState("Counters Not Downloaded Yet", message: "Counters download in the background. Check your connection, then reopen the app.")
        } else if search.isEmpty {
            directory
        } else {
            CounterSearchResultsView(
                results: results(in: activeLevels), search: search, summary: summary,
                hiddenMatchCount: hiddenMatchCount, open: go
            )
        }
    }

    /// The heading and its Compare link; stacked at accessibility sizes so neither is squeezed.
    private func sectionHeader(_ section: CounterHomeSection) -> some View {
        SectionHeader(section.section.title) {
            if section.canCompare {
                Button("Compare") { go(.section(section.section)) }
                    .buttonStyle(.paperSecondaryInline)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityLabel("Compare \(section.section.title)")
            }
        }
        .textCase(nil)
    }

    /// "Start here": the board's nine everyday counters as tiles, three across (one at
    /// accessibility sizes); counters hidden by the level settings drop out.
    @ViewBuilder private var startHere: some View {
        let tiles = CounterHome.startHere(counters(in: settings))
        if !tiles.isEmpty {
            Section {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 1 : 3),
                    spacing: 8
                ) {
                    ForEach(tiles) { counter in
                        Button { go(.counter(counter, focus: nil)) } label: { CounterTile(counter: counter) }
                            .buttonStyle(.plain)
                    }
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } header: {
                SectionHeader("Start here").textCase(nil)
            }
        }
    }

    private var directory: some View {
        let sections = home
        return List {
            startHere
            ForEach(sections) { section in
                Section {
                    ForEach(section.rows) { row in
                        Button {
                            go(.counter(row.counter, focus: nil))
                        } label: {
                            DirectoryRow(counter: row.counter)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                        .paperRow()
                    }
                } header: {
                    sectionHeader(section)
                }
            }
            if !sections.isEmpty {
                Section {
                    Button {
                        go(.patterns)
                    } label: {
                        HStack {
                            Label("Why counters change sound", systemImage: "waveform")
                            Spacer(minLength: 0)
                            RowChevron()
                        }
                        .foregroundStyle(palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .paperRow()
                }
                ReviewSummaryLine(noun: "counters", summary: ReviewSummary(counters(in: settings)))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .overlay {
            if sections.isEmpty {
                PaperEmptyState("No counters in your levels", message: "Show more levels in Settings to see them here.")
            }
        }
    }
}

/// A "Start here" tile: the counter in Mincho over what it counts, on a paper card.
private struct CounterTile: View {
    let counter: Counter
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 2) {
            JapaneseText(counter.counter)
                .font(.headword(.title))
                .foregroundStyle(palette.ink)
            Text(counter.meaning)
                .font(.caption2)
                .foregroundStyle(palette.muted)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 6)
        }
        .frame(maxWidth: .infinity, minHeight: 104)
        .paperCard(cornerRadius: 14, fillsWidth: true)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}
