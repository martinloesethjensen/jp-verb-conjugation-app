import SwiftUI
import VerbKit

extension GrammarSlot {
    /// The slot's name on chips and table headers.
    var title: String {
        switch self {
        case .plain: "now"
        case .plainNeg: "not"
        case .plainPast: "past"
        case .plainPastNeg: "past not"
        case .stem: "stem"
        case .te: "て-form"
        }
    }

    var explanation: String {
        switch self {
        case .plain: "The plain present: the dictionary form, with だ for な-adjectives and nouns."
        case .plainNeg: "The plain negative (ない-form)."
        case .plainPast: "The plain past (た-form)."
        case .plainPastNeg: "The plain past negative (なかった-form)."
        case .stem: "A verb's ます form without ます, or an adjective without い or な."
        case .te: "The て-form, which joins clauses and many helpers."
        }
    }
}

/// The four word types side by side in every slot, then what each slot is for and which
/// lessons use it. Patterns attach to these forms, so learning them once covers every lesson.
struct BuildingBlocksView: View {
    @Environment(VerbStore.self) private var verbStore
    @Environment(WordsStore.self) private var wordsStore
    @State private var picks: [WordClass: String] = [:]

    private static let classes: [WordClass] = [.verb, .iAdjective, .naAdjective, .noun]
    private static let defaults: [WordClass: String] = [
        .verb: "たべる", .iAdjective: "たかい", .naAdjective: "しずか", .noun: "あめ",
    ]

    private func candidates(_ wordClass: WordClass) -> [SlotSource] {
        wordClass == .verb ? verbStore.verbs : wordsStore.words(of: wordClass)
    }

    private func source(_ wordClass: WordClass) -> SlotSource? {
        let wanted = picks[wordClass] ?? Self.defaults[wordClass]
        let all = candidates(wordClass)
        return all.first { $0.dict == wanted } ?? all.first
    }

    private func lessons(using slot: GrammarSlot) -> [GrammarPoint] {
        verbStore.grammarPoints.filter { $0.attachment.contains { $0.slots.contains(slot) } }
    }

    var body: some View {
        List {
            Section {
                Text("Most grammar is a building block plus a pattern. Learn these forms once, then each lesson only says which block it takes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Example words") {
                ForEach(Self.classes, id: \.self) { wordClass in
                    let options = candidates(wordClass).map(\.dict)
                    if !options.isEmpty {
                        Picker(wordClass.displayName, selection: Binding(
                            get: { source(wordClass)?.dict ?? "" },
                            set: { picks[wordClass] = $0 }
                        )) {
                            ForEach(options, id: \.self) { Text($0).tag($0) }
                        }
                    }
                }
            }
            ForEach(GrammarSlot.allCases, id: \.self) { slot in
                Section {
                    ForEach(Self.classes, id: \.self) { wordClass in
                        let form = source(wordClass)?.form(for: slot)
                        LabeledContent(wordClass.displayName) {
                            JapaneseText(form ?? "none")
                                .font(form == nil ? .body : .title3.weight(.semibold))
                                .foregroundStyle(form == nil ? .secondary : .primary)
                        }
                    }
                    let users = lessons(using: slot)
                    DisclosureGroup(users.count == 1 ? "Used by 1 lesson" : "Used by \(users.count) lessons") {
                        Text(slot.explanation).font(.callout).foregroundStyle(.secondary)
                        ForEach(users) { point in
                            JapaneseText(point.title)
                        }
                    }
                } header: {
                    Text(slot.title)
                }
            }
        }
        .navigationTitle("Building blocks")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// Building blocks as a sheet with a Done button, for the Grammar list and the lesson chips.
struct BuildingBlocksSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            BuildingBlocksView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
