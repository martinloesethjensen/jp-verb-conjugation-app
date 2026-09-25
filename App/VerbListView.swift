import SwiftUI
import VerbKit

private let githubSuggestVerbURL = URL(string: "https://github.com/martinloesethjensen/jp-verb-conjugation-app/issues/new?template=add-verb.yml")!

struct VerbListView: View {
    @Environment(VerbStore.self) private var verbStore
    @Binding var selection: Verb?
    @State private var search = ""
    @State private var typeFilter: VerbType?
    @State private var showGuide = false

    private var filtered: [Verb] {
        verbStore.verbs.filter { matchesType($0, filter: typeFilter) && matchesSearch($0, query: search) }
    }

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

                DisclosureGroup("Verb type guide", isExpanded: $showGuide) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("**Ru-verb (一段):** ends in -eru or -iru. Drop る and add the ending. Exceptions: はいる, かえる, きる look like ru-verbs but are u-verbs.")
                        Text("**U-verb (五段):** ends in any -u sound. If not -eru/-iru, it's a u-verb.")
                        Text("**Irregular:** only する and くる (and compounds like べんきょうする).")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                TeFormLegend()
            }

            Section {
                ForEach(filtered) { verb in
                    Button {
                        selection = verb
                    } label: {
                        VerbRow(verb: verb)
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Link("Suggest a verb", destination: githubSuggestVerbURL)
                    .font(.caption)
            }
        }
        .searchable(text: $search, prompt: "Search hiragana, kanji, or English…")
        .navigationTitle("動詞活用表")
        .overlay {
            if !search.isEmpty && filtered.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
    }
}
