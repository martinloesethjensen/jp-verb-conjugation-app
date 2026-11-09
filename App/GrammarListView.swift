import SwiftUI
import VerbKit

struct GrammarRow: View {
    let point: GrammarPoint
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                JapaneseText(point.title)
                    .font(.headword(.title3))
                    .foregroundStyle(palette.ink)
                LevelBadge(range: point.levelRange)
            }
            JapaneseText(point.summary)
                .font(.subheadline)
                .foregroundStyle(palette.muted)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}

enum GrammarListMode: String, CaseIterable, Identifiable {
    case byLevel, byLesson
    var id: String { rawValue }
    var title: String { self == .byLevel ? "By level" : "My course" }
}

struct GrammarListView: View {
    @Environment(VerbStore.self) private var verbStore
    @Environment(\.furiganaDictionary) private var furigana
    @Binding var selection: GrammarPoint?
    var onSettings: () -> Void
    @State private var search = ""
    @State private var scope: LevelScope = .mine
    @State private var showingBlocks = false
    @State private var showingMistakes = false
    @Environment(CountersStore.self) private var countersStore
    @Environment(\.openRoute) private var openRoute
    @State private var showingCourse = false
    @Environment(CourseStore.self) private var courseStore
    @AppStorage("grammarListMode", store: .appGroup) private var modeRaw = GrammarListMode.byLevel.rawValue
    @FocusState private var searchFocused: Bool
    @AppStorage(LevelSettings.defaultsKey, store: .appGroup) private var hiddenLevelsRaw = ""
    @Environment(\.palette) private var palette

    private var settings: LevelSettings { LevelSettings(rawValue: hiddenLevelsRaw) }
    private var availableLevels: Set<JLPTLevel> {
        verbStore.grammarPoints.levels()
    }
    private var levelsHidden: Bool { settings.anyHidden(among: availableLevels) }
    private var summary: String { settings.summary(among: availableLevels) ?? "" }

    private func matching(in levels: LevelSettings) -> [GrammarPoint] {
        // Best match first: title and keyword hits, then summary, usage headings, then examples.
        verbStore.grammarPoints.visible(in: levels).searched(for: search, furigana: furigana)
    }

    /// Pitfalls that match the search, within the visible levels, for the results section.
    private var matchingMistakes: [CommonMistake] {
        guard !search.isEmpty, verbStore.hasGrammar else { return [] }
        return CommonMistakes.build(grammar: verbStore.grammarPoints, counters: countersStore.counters)
            .visible(in: currentLevels)
            .filter { matchesMistakeSearch($0, query: search, furigana: furigana) }
    }

    private var mode: GrammarListMode { GrammarListMode(rawValue: modeRaw) ?? .byLevel }
    private var modeBinding: Binding<GrammarListMode> {
        Binding(get: { mode }, set: { modeRaw = $0.rawValue })
    }

    /// One section per lesson of My course, each with its visible, matching points; empty sections are dropped.
    private func lessonSections(in levels: LevelSettings) -> [(lesson: CourseLesson, points: [GrammarPoint])] {
        guard let course = courseStore.course else { return [] }
        let visible = matching(in: levels)
        let byID = Dictionary(visible.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return course.resolved(points: verbStore.grammarPoints, textbooks: verbStore.textbooks).compactMap { lesson in
            let points = lesson.grammarIDs.compactMap { byID[$0] }
            return points.isEmpty ? nil : (lesson, points)
        }
    }

    private var currentLevels: LevelSettings { scope == .mine ? settings : LevelSettings() }
    private var sections: [(lesson: CourseLesson, points: [GrammarPoint])] { lessonSections(in: currentLevels) }

    /// My course groups lessons by course lesson, but only while not searching: a search looks
    /// through every lesson, best match first, whichever chip is on.
    private var showsCourse: Bool { mode == .byLesson && search.isEmpty }

    private var filtered: [GrammarPoint] {
        showsCourse ? sections.flatMap(\.points) : matching(in: currentLevels)
    }

    /// Matches hidden by the level setting, for the current search.
    private var hiddenMatchCount: Int {
        guard scope == .mine, levelsHidden, showsCourse || !search.isEmpty else { return 0 }
        let all = !showsCourse ? matching(in: LevelSettings()).count
            : lessonSections(in: LevelSettings()).reduce(0) { $0 + $1.points.count }
        return all - filtered.count
    }

    /// Lessons grouped by their lowest level, N5 first; lessons without a level last.
    private var levelGroups: [(title: String, points: [GrammarPoint])] {
        let grouped = Dictionary(grouping: filtered) { $0.levelRange?.lowerBound }
        var groups = JLPTLevel.allCases.compactMap { level in
            grouped[level].map { (level.displayName, $0) }
        }
        if let other = grouped[nil] { groups.append(("Other", other)) }
        return groups
    }

    private var mistakeCount: Int {
        CommonMistakes.build(grammar: verbStore.grammarPoints, counters: countersStore.counters)
            .visible(in: currentLevels).count
    }

    private func shortcut(_ title: String, detail: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(palette.muted)
            }
            .paperCard(cornerRadius: 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Whether the overlay shows a message (nothing downloaded, no course, no lessons, no match);
    /// the shortcut cards then stay out of the way so the two never overlap.
    private var showsEmptyState: Bool {
        !verbStore.hasGrammar
            || (showsCourse && courseStore.course == nil)
            || (showsCourse && lessonSections(in: LevelSettings()).isEmpty)
            || (filtered.isEmpty && matchingMistakes.isEmpty)
    }

    /// "By level" / "My course": the first row, so it scrolls with the list instead of floating over it.
    private var modeChips: some View {
        HStack(spacing: 8) {
            ForEach(GrammarListMode.allCases) { option in
                Button {
                    modeBinding.wrappedValue = option
                } label: {
                    FilterChip(option.title, isOn: mode == option)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(mode == option ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }

    // Same row pattern as VerbListView: an explicit Button
    // sets the selection, and .tag keeps List's own selection
    // in sync (List(selection:) alone matches the row's id,
    // not the element, so taps would silently do nothing).
    private func pointRow(_ point: GrammarPoint) -> some View {
        Button {
            selection = point
        } label: {
            GrammarRow(point: point)
        }
        .buttonStyle(.plain)
        .tag(point)
        .paperRow()
    }

    var body: some View {
        List(selection: $selection) {
            // Their own section, so the first card below keeps its rounded top.
            if verbStore.hasGrammar { Section { modeChips } }
            if search.isEmpty && verbStore.hasGrammar && !showsEmptyState {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        shortcut("Building blocks", detail: "Forms lessons attach to", systemImage: "square.stack.3d.up") {
                            showingBlocks = true
                        }
                        shortcut("Common mistakes", detail: "\(mistakeCount) slips, by theme", systemImage: "exclamationmark.triangle") {
                            showingMistakes = true
                        }
                    }
                    VStack(spacing: 10) {
                        shortcut("Building blocks", detail: "Forms lessons attach to", systemImage: "square.stack.3d.up") {
                            showingBlocks = true
                        }
                        shortcut("Common mistakes", detail: "\(mistakeCount) slips, by theme", systemImage: "exclamationmark.triangle") {
                            showingMistakes = true
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            if mode == .byLevel && search.isEmpty {
                ForEach(levelGroups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.points) { point in pointRow(point) }
                    }
                }
            } else if !showsCourse {
                ForEach(filtered) { point in pointRow(point) }
            } else {
                ForEach(sections, id: \.lesson.id) { section in
                    Section {
                        ForEach(section.points) { point in pointRow(point) }
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.lesson.name)
                            if section.lesson.unreviewed {
                                Text("unreviewed").font(.caption2).textCase(nil)
                            }
                        }
                    }
                }
            }
            if !matchingMistakes.isEmpty {
                Section("Common mistakes") {
                    ForEach(matchingMistakes) { mistake in
                        Button { openRoute(mistake.source) } label: { MistakeRow(mistake: mistake) }
                            .buttonStyle(.plain)
                    }
                }
            }
            if !filtered.isEmpty && hiddenMatchCount > 0 {
                HiddenMatchesRow(count: hiddenMatchCount)
            }
            if search.isEmpty && verbStore.hasGrammar && !showsEmptyState {
                ReviewSummaryLine(noun: "lessons", summary: ReviewSummary(verbStore.grammarPoints.visible(in: currentLevels)))
            }
        }
        // Always shown: with only the chips in the list (no course yet) the drawer would hide it.
        .inlineSearch(text: $search, prompt: "Search grammar…", focused: $searchFocused, alwaysVisible: true)
        .levelScopeBar(isActive: levelsHidden, scope: $scope)
        .onChange(of: search) { if search.isEmpty { scope = .mine } }
        .paperBackground()
        .navigationTitle("Grammar")
        .sheet(isPresented: $showingBlocks) { BuildingBlocksSheet() }
        .sheet(isPresented: $showingMistakes) { CommonMistakesSheet() }
        .dismissOnLink {
            showingBlocks = false
            showingMistakes = false
        }
        .sheet(isPresented: $showingCourse) {
            NavigationStack {
                MyCourseView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingCourse = false }
                        }
                    }
            }
        }
        .navigationSubtitle(scope == .mine ? summary : "")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("More", systemImage: "ellipsis") {
                    Button("Settings", systemImage: "gearshape", action: onSettings)
                    ReportProblemButton(item: "")
                }
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
                    .buttonStyle(.paper)
                }
            } else if showsCourse && courseStore.course == nil {
                ContentUnavailableView {
                    Label("No course yet", systemImage: "books.vertical")
                } description: {
                    Text("Set up My course to see grammar by lesson.")
                } actions: {
                    Button("Set Up My Course") { showingCourse = true }
                        .buttonStyle(.paper)
                }
            } else if showsCourse && lessonSections(in: LevelSettings()).isEmpty {
                ContentUnavailableView {
                    Label("No lessons yet", systemImage: "books.vertical")
                } description: {
                    Text("Add lessons in My course.")
                } actions: {
                    Button("Set Up My Course") { showingCourse = true }
                        .buttonStyle(.paper)
                }
            } else if filtered.isEmpty && matchingMistakes.isEmpty {
                if hiddenMatchCount > 0 {
                    NoMatchInLevelsView(summary: summary, hiddenCount: hiddenMatchCount)
                } else {
                    ContentUnavailableView.search(text: search)
                }
            }
        }
    }
}
