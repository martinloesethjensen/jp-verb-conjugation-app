import SwiftUI
import VerbKit

struct GrammarRow: View {
    let point: GrammarPoint

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                JapaneseText(point.title)
                    .font(.title3.weight(.bold))
                LevelBadge(range: point.levelRange)
            }
            JapaneseText(point.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

enum GrammarListMode: String, CaseIterable, Identifiable {
    case byLevel, byLesson
    var id: String { rawValue }
    var title: String { self == .byLevel ? "By level" : "By lesson" }
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

    private var filtered: [GrammarPoint] {
        mode == .byLevel ? matching(in: currentLevels) : sections.flatMap(\.points)
    }

    /// Matches hidden by the level setting, for the current search.
    private var hiddenMatchCount: Int {
        guard scope == .mine, levelsHidden, mode == .byLesson || !search.isEmpty else { return 0 }
        let all = mode == .byLevel ? matching(in: LevelSettings()).count
            : lessonSections(in: LevelSettings()).reduce(0) { $0 + $1.points.count }
        return all - filtered.count
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
    }

    var body: some View {
        List(selection: $selection) {
            if search.isEmpty && verbStore.hasGrammar {
                Section {
                    Button {
                        showingBlocks = true
                    } label: {
                        Label("Building blocks", systemImage: "square.stack.3d.up")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button {
                        showingMistakes = true
                    } label: {
                        Label("Common mistakes", systemImage: "exclamationmark.triangle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } footer: {
                    Text("The forms every lesson attaches to, and the slips learners make most.")
                }
            }
            if mode == .byLevel {
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
            if search.isEmpty && verbStore.hasGrammar {
                ReviewSummaryLine(noun: "lessons", summary: ReviewSummary(verbStore.grammarPoints.visible(in: currentLevels)))
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if verbStore.hasGrammar {
                Picker("Group by", selection: modeBinding) {
                    ForEach(GrammarListMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .inlineSearch(text: $search, prompt: "Search grammar…", focused: $searchFocused)
        .levelScopeBar(isActive: levelsHidden, scope: $scope)
        .onChange(of: search) { if search.isEmpty { scope = .mine } }
        .navigationTitle("Grammar")
        .sheet(isPresented: $showingBlocks) { BuildingBlocksSheet() }
        .sheet(isPresented: $showingMistakes) { CommonMistakesSheet() }
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
                    .buttonStyle(.glassProminent)
                }
            } else if mode == .byLesson && courseStore.course == nil {
                ContentUnavailableView {
                    Label("No course yet", systemImage: "books.vertical")
                } description: {
                    Text("Set up My course to see grammar by lesson.")
                } actions: {
                    Button("Set Up My Course") { showingCourse = true }
                        .buttonStyle(.glassProminent)
                }
            } else if mode == .byLesson && search.isEmpty && lessonSections(in: LevelSettings()).isEmpty {
                ContentUnavailableView {
                    Label("No lessons yet", systemImage: "books.vertical")
                } description: {
                    Text("Add lessons in My course.")
                } actions: {
                    Button("Set Up My Course") { showingCourse = true }
                        .buttonStyle(.glassProminent)
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
