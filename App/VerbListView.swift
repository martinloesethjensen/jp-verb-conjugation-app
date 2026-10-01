import SwiftUI
import VerbKit

private let githubSuggestVerbURL = URL(string: "https://github.com/martinloesethjensen/jp-verb-conjugation-app/issues/new?template=add-verb.yml")!

struct VerbListView: View {
    @Environment(VerbStore.self) private var verbStore
    @Binding var selection: Verb?
    var onRandomQuiz: () -> Void
    var onSettings: () -> Void
    @State private var search = ""
    @State private var typeFilter: VerbType?
    @State private var teFilter: TeGroup?
    @State private var showGuide = false

    private var filtered: [Verb] {
        verbStore.verbs.filter {
            matchesType($0, filter: typeFilter)
                && matchesTeGroup($0, filter: teFilter)
                && matchesSearch($0, query: search)
        }
    }

    private var hasFilters: Bool { typeFilter != nil || teFilter != nil }

    var body: some View {
        List(selection: $selection) {
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
        .safeAreaInset(edge: .top, spacing: 0) {
            TeFormFilter(selection: $teFilter)
                .padding(.vertical, 6)
        }
        .searchable(text: $search, prompt: "Search hiragana, kanji, or English…")
        .navigationTitle("早見表")
        .sheet(isPresented: $showGuide) { VerbGuideSheet() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Guide", systemImage: "info.circle") { showGuide = true }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Random Quiz", systemImage: "gamecontroller", action: onRandomQuiz)
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
