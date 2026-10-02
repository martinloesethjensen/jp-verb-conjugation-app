import SwiftUI
import VerbKit

private let githubSuggestVerbURL = URL(string: "https://github.com/martinloesethjensen/jp-verb-conjugation-app/issues/new?template=add-verb.yml")!

struct VerbListView: View {
    @Environment(VerbStore.self) private var verbStore
    @Binding var selection: Verb?
    @Binding var showGuide: Bool
    var onProgress: () -> Void
    var onRandomQuiz: () -> Void
    var onSettings: () -> Void
    @State private var search = ""
    @State private var typeFilter: VerbType?
    @State private var teFilter: TeGroup?
    /// True once the filters block has scrolled off screen, which is when the
    /// back-to-top button appears.
    @State private var filtersOffscreen = false
    @State private var scope: LevelScope = .mine
    @FocusState private var searchFocused: Bool
    @State private var scrolledAwayFromTop = false
    @State private var scrollToTop: (() -> Void)?
    @AppStorage(LevelSettings.defaultsKey, store: .appGroup) private var hiddenLevelsRaw = ""

    private var settings: LevelSettings { LevelSettings(rawValue: hiddenLevelsRaw) }
    private var availableLevels: Set<JLPTLevel> {
        verbStore.verbs.levels()
    }
    private var levelsHidden: Bool { settings.anyHidden(among: availableLevels) }
    private var effectiveSettings: LevelSettings { scope == .mine ? settings : LevelSettings() }

    private static let filtersID = "filters"

    private func matching(in levels: LevelSettings) -> [Verb] {
        verbStore.verbs.visible(in: levels).filter {
            matchesType($0, filter: typeFilter)
                && matchesTeGroup($0, filter: teFilter)
                && matchesSearch($0, query: search)
        }
    }

    private var filtered: [Verb] { matching(in: effectiveSettings) }

    /// Matches hidden by the level setting, for the current search and filters.
    private var hiddenMatchCount: Int {
        guard scope == .mine, levelsHidden, !search.isEmpty else { return 0 }
        return matching(in: LevelSettings()).count - filtered.count
    }

    private var hasFilters: Bool { typeFilter != nil || teFilter != nil }

    /// "って · Ru-verbs": which filters are on, shown under the title so they stay
    /// visible after the filters themselves have scrolled away. Empty when none is on.
    private var filterSummary: String {
        var parts: [String] = []
        if let teFilter, let rule = TeFormRule.all.first(where: { $0.group == teFilter }) {
            parts.append(rule.result)
        }
        if let typeFilter { parts.append(typeFilter.filterTitle) }
        if scope == .mine, let levels = settings.summary(among: availableLevels) { parts.append(levels) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: $selection) {
                Section {
                    // The filters scroll with the list, so nothing is pinned over the rows.
                    TeFormFilter(type: $typeFilter, selection: $teFilter)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .id(Self.filtersID)
                        .onAppear { filtersOffscreen = false }
                        .onDisappear { filtersOffscreen = true }
                }
                #if os(iOS)
                // No section margin, so the chip row spans the full width and never clips.
                .listSectionMargins(.horizontal, 0)
                #endif

                Section {
                    if filtered.isEmpty {
                        if hiddenMatchCount > 0 {
                            NoMatchInLevelsView(
                                summary: settings.summary(among: availableLevels) ?? "",
                                hiddenCount: hiddenMatchCount
                            )
                        } else {
                            emptyState
                        }
                    }
                    ForEach(filtered) { verb in
                        Button {
                            selection = verb
                        } label: {
                            VerbRow(verb: verb)
                        }
                        .buttonStyle(.plain)
                        .tag(verb)
                    }
                    if !filtered.isEmpty && hiddenMatchCount > 0 {
                        HiddenMatchesRow(count: hiddenMatchCount)
                    }
                } footer: {
                    Link("Suggest a verb", destination: githubSuggestVerbURL)
                        .font(.caption)
                }
            }
            .inlineSearch(text: $search, prompt: "Search verbs…", focused: $searchFocused)
            .levelScopeBar(isActive: levelsHidden, scope: $scope)
            .onChange(of: search) { if search.isEmpty { scope = .mine } }
            .onAppear { scrollToTop = { withAnimation { proxy.scrollTo(Self.filtersID, anchor: .top) } } }
            #if os(iOS)
            .listSectionSpacing(.compact)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 44
            } action: { _, scrolled in
                scrolledAwayFromTop = scrolled
            }
            .overlay(alignment: .bottomTrailing) {
                if filtersOffscreen {
                    Button {
                        withAnimation { proxy.scrollTo(Self.filtersID, anchor: .top) }
                    } label: {
                        Label("Back to top", systemImage: "arrow.up")
                            .labelStyle(.iconOnly)
                            .font(.headline)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .padding(.trailing, 20)
                    .padding(.bottom, 12)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.smooth, value: filtersOffscreen)
            #endif
        }
        .navigationTitle("早見表")
        .navigationSubtitle(filterSummary)
        .sheet(isPresented: $showGuide) { VerbGuideSheet() }
        .toolbar {
            #if os(iOS)
            if scrolledAwayFromTop {
                ToolbarItem(placement: .primaryAction) {
                    Button("Search", systemImage: "magnifyingglass") {
                        scrollToTop?()
                        searchFocused = true
                    }
                }
            }
            #endif
            ToolbarItem(placement: .primaryAction) {
                // The toolbar drops a Label's title, so the text is spelled out to keep "Quiz" visible.
                Button(action: onRandomQuiz) {
                    HStack(spacing: 4) {
                        Image(systemName: "gamecontroller")
                        Text("Quiz")
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu("More", systemImage: "ellipsis") {
                    Button("Progress", systemImage: "chart.bar", action: onProgress)
                    Button("Guide", systemImage: "info.circle") { showGuide = true }
                    Button("Settings", systemImage: "gearshape", action: onSettings)
                    ReportProblemButton(item: "")
                }
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
        if !search.isEmpty && !hasFilters {
            ContentUnavailableView.search(text: search)
        } else {
            ContentUnavailableView {
                Label("No verbs match", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text(search.isEmpty ? "No verb fits these filters." : "No verb fits “\(search)” with these filters.")
            } actions: {
                Button("Clear filters") { typeFilter = nil; teFilter = nil }
            }
        }
    }
}
