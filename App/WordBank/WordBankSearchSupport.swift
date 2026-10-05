import SwiftUI
import VerbKit

// MARK: - Tokens

extension WordBankToken {
    /// What a token is called in the search field, chips and subtitle.
    @MainActor
    func title(in store: WordBankStore) -> String {
        switch self {
        case .dialectTag(let id): store.dialectTags.first { $0.id == id }?.name ?? "Deleted tag"
        case .region(let region): region.name
        case .prefecture(let prefecture): prefecture.name
        case .customTag(let id): store.customTags.first { $0.id == id }?.name ?? "Deleted tag"
        case .folder(let id): store.tree.folder(id)?.name ?? "Deleted folder"
        case .kind(let kind): kind.rawValue.capitalized
        case .wordClass(let wordClass): wordClass.rawValue.capitalized
        case .unfiled: "Unfiled"
        case .noDialectTag: "No dialect tag"
        }
    }

    var systemImage: String {
        switch self {
        case .dialectTag, .prefecture: "mappin.and.ellipse"
        case .region: "map"
        case .customTag: "number"
        case .folder: "folder"
        case .kind, .wordClass: "textformat"
        case .unfiled: "tray"
        case .noDialectTag: "mappin.slash"
        }
    }
}

/// A token as it shows inside the search field.
struct WordBankTokenLabel: View {
    @Environment(WordBankStore.self) private var store
    let token: WordBankToken

    var body: some View {
        Label(token.title(in: store), systemImage: token.systemImage)
    }
}

// MARK: - The search field

/// Whether a search inside a folder looks only in it (and its subfolders) or everywhere.
enum WordBankSearchScope: Hashable {
    case thisFolder, allEntries
}

/// The search field with tokens and suggested tokens, and, inside a folder, the scope switch.
struct WordBankSearchable: ViewModifier {
    @Binding var text: String
    @Binding var tokens: [WordBankToken]
    @Binding var suggested: [WordBankToken]
    @Binding var scope: WordBankSearchScope
    var focused: FocusState<Bool>.Binding
    let hasScopes: Bool
    let onSubmit: () -> Void

    func body(content: Content) -> some View {
        let searchable = content
            .searchable(
                text: $text, tokens: $tokens, suggestedTokens: $suggested,
                placement: placement, prompt: "Search word bank…"
            ) { token in
                WordBankTokenLabel(token: token)
            }
            .searchFocused(focused)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .onSubmit(of: .search, onSubmit)
        if hasScopes {
            searchable.searchScopes($scope) {
                Text("This folder").tag(WordBankSearchScope.thisFolder)
                Text("All entries").tag(WordBankSearchScope.allEntries)
            }
        } else {
            searchable
        }
    }

    private var placement: SearchFieldPlacement {
        #if os(iOS)
        .navigationBarDrawer(displayMode: .automatic)
        #else
        .automatic
        #endif
    }
}

// MARK: - Chips

/// Dialect, Kind and Tag menus under the search field. They add and remove the same tokens
/// the field holds, so a chip and its token are always in step.
struct WordBankSearchChips: View {
    @Environment(WordBankStore.self) private var store
    @Binding var tokens: [WordBankToken]

    private func toggle(_ token: WordBankToken) {
        if let index = tokens.firstIndex(of: token) { tokens.remove(at: index) } else { tokens.append(token) }
    }

    private func has(_ token: WordBankToken) -> Bool { tokens.contains(token) }

    private var dialectActive: Bool {
        tokens.contains { token in
            switch token {
            case .dialectTag, .region, .prefecture, .noDialectTag: true
            default: false
            }
        }
    }

    private var kindActive: Bool {
        tokens.contains { if case .kind = $0 { true } else { false } }
    }

    private var tagActive: Bool {
        tokens.contains { if case .customTag = $0 { true } else { false } }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Dialect", active: dialectActive) { dialectMenu }
                chip("Kind", active: kindActive) { kindMenu }
                chip("Tag", active: tagActive) { tagMenu }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
    }

    // MARK: Menus

    @ViewBuilder
    private var dialectMenu: some View {
        Button { toggle(.noDialectTag) } label: {
            Label("No dialect tag", systemImage: has(.noDialectTag) ? "checkmark" : "mappin.slash")
        }
        ForEach(Region.allCases, id: \.self) { region in
            let tags = store.dialectTags.filter { $0.region == region }.sorted { $0.name < $1.name }
            if !tags.isEmpty {
                Section(region.name) {
                    Button { toggle(.region(region)) } label: {
                        Label("All of \(region.name)", systemImage: has(.region(region)) ? "checkmark" : "map")
                    }
                    ForEach(tags) { tag in
                        Button { toggle(.dialectTag(tag.id)) } label: {
                            Label(tag.name, systemImage: has(.dialectTag(tag.id)) ? "checkmark" : "mappin.and.ellipse")
                        }
                    }
                }
            }
        }
        if store.dialectTags.isEmpty {
            Text("No dialect tags yet")
        }
    }

    @ViewBuilder
    private var kindMenu: some View {
        ForEach(EntryKind.allCases, id: \.self) { kind in
            Button {
                // One kind at a time: picking another replaces it.
                let wasOn = has(.kind(kind))
                tokens.removeAll { if case .kind = $0 { true } else { false } }
                if !wasOn { tokens.append(.kind(kind)) }
            } label: {
                Label(kind.rawValue.capitalized, systemImage: has(.kind(kind)) ? "checkmark" : "textformat")
            }
        }
    }

    @ViewBuilder
    private var tagMenu: some View {
        ForEach(store.customTags.sorted { $0.name < $1.name }) { tag in
            Button { toggle(.customTag(tag.id)) } label: {
                Label(tag.name, systemImage: has(.customTag(tag.id)) ? "checkmark" : "number")
            }
        }
        if store.customTags.isEmpty {
            Text("No tags yet")
        }
    }

    private func chip<Content: View>(_ title: String, active: Bool, @ViewBuilder menu: () -> Content) -> some View {
        Menu {
            menu()
        } label: {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: "chevron.down").font(.caption2.weight(.bold)).accessibilityHidden(true)
            }
            .font(.callout.weight(active ? .bold : .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .chipBackground(nil)
            .overlay { if active { Capsule().strokeBorder(Color.primary, lineWidth: 2) } }
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}

// MARK: - Why a result matched

/// "Standard: ありがとう" with the matched part in bold and the accent colour. VoiceOver reads
/// the same words.
struct MatchExplanationLabel: View {
    let explanation: WordBankMatch.Explanation

    private static func name(_ field: WordBankField) -> String {
        switch field {
        case .text: "Text"
        case .reading: "Reading"
        case .kanjiSpelling: "Written"
        case .equivalent: "Standard"
        case .sense: "Meaning"
        case .tag: "Tag"
        case .senseNote: "Note"
        case .folder: "Folder"
        case .notes: "Notes"
        }
    }

    private var snippet: AttributedString {
        var text = AttributedString(explanation.snippet)
        if let range = explanation.range, let matched = Range(range, in: text) {
            text[matched].inlinePresentationIntent = .stronglyEmphasized
            text[matched].foregroundColor = .accentColor
        }
        return text
    }

    var body: some View {
        (Text("\(Self.name(explanation.field)): ").foregroundStyle(.secondary) + Text(snippet))
            .font(.footnote)
            .lineLimit(2)
            .accessibilityLabel("Matched in \(Self.name(explanation.field)): \(explanation.snippet)")
    }
}

// MARK: - Recent searches

/// The last searches, newest first: tap to run one again, swipe to remove it.
struct RecentSearchesSection: View {
    @Environment(WordBankStore.self) private var store
    let searches: [WordBankQuery]
    let onPick: (WordBankQuery) -> Void
    let onRemove: (WordBankQuery) -> Void
    let onClear: () -> Void

    var body: some View {
        Section {
            ForEach(searches, id: \.self) { query in
                Button { onPick(query) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            if !query.text.isEmpty { Text(query.text) }
                            if !query.tokens.isEmpty {
                                Text(query.tokens.map { $0.title(in: store) }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button("Remove", systemImage: "trash", role: .destructive) { onRemove(query) }
                }
            }
        } header: {
            HStack {
                Text("Recent searches")
                Spacer()
                Button("Clear", action: onClear).font(.footnote).textCase(nil)
            }
        }
    }
}
