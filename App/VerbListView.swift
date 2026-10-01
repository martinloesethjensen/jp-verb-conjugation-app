import SwiftUI
import VerbKit

private let githubSuggestVerbURL = URL(string: "https://github.com/martinloesethjensen/jp-verb-conjugation-app/issues/new?template=add-verb.yml")!

struct VerbListView: View {
    @Environment(VerbStore.self) private var verbStore
    @Binding var selection: Verb?
    @Binding var showGuide: Bool
    var onRandomQuiz: () -> Void
    var onSettings: () -> Void
    @State private var search = ""
    @State private var typeFilter: VerbType?
    @State private var teFilter: TeGroup?
    /// True once the filters block has scrolled off screen, which is when the
    /// back-to-top button appears.
    @State private var filtersOffscreen = false


    private static let filtersID = "filters"

    private var filtered: [Verb] {
        verbStore.verbs.filter {
            matchesType($0, filter: typeFilter)
                && matchesTeGroup($0, filter: teFilter)
                && matchesSearch($0, query: search)
        }
    }

    private var hasFilters: Bool { typeFilter != nil || teFilter != nil }

    /// "って · Ru-verbs": which filters are on, shown under the title so they stay
    /// visible after the filters themselves have scrolled away. Empty when none is on.
    private var filterSummary: String {
        var parts: [String] = []
        if let teFilter, let rule = TeFormRule.all.first(where: { $0.group == teFilter }) {
            parts.append(rule.result)
        }
        switch typeFilter {
        case .irregular?: parts.append("Irregular")
        case .ru?: parts.append("Ru-verbs")
        case .u?: parts.append("U-verbs")
        case nil: break
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: $selection) {
                Section {
                    // The filters scroll with the list, so nothing is pinned over the rows.
                    TeFormFilter(selection: $teFilter)
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
                    Picker("Type", selection: $typeFilter) {
                        Text("All").tag(VerbType?.none)
                        Text("Irregular").tag(VerbType?.some(.irregular))
                        Text("Ru-verbs").tag(VerbType?.some(.ru))
                        Text("U-verbs").tag(VerbType?.some(.u))
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                }

                Section {
                    if filtered.isEmpty { emptyState }
                    ForEach(filtered) { verb in
                        Button {
                            selection = verb
                        } label: {
                            VerbRow(verb: verb)
                        }
                        .buttonStyle(.plain)
                        .tag(verb)
                    }
                } footer: {
                    Link("Suggest a verb", destination: githubSuggestVerbURL)
                        .font(.caption)
                }
            }
            .searchable(text: $search, prompt: "Search hiragana, kanji, romaji, or English…")
            #if os(iOS)
            .listSectionSpacing(.compact)
            // The search field collapses to a button in the navigation bar, so search
            // stays one tap away however far the list has scrolled.
            .searchToolbarBehavior(.minimize)
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
            ToolbarItem(placement: .primaryAction) {
                Button("Guide", systemImage: "info.circle") { showGuide = true }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Random Quiz", systemImage: "gamecontroller", action: onRandomQuiz)
            }
            ToolbarItem(placement: .secondaryAction) {
                ReportProblemButton(item: "")
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Settings", systemImage: "gearshape", action: onSettings)
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
