import SwiftUI
import Translation
import VerbKit

/// A long-press (right-click) menu that acts on one piece of Japanese text:
/// Copy, Open in Jisho, Look up form (when the text has a verb the matcher finds), stroke order for
/// its kanji,
/// and, for sentences, a Translate submenu with Apple Translate, DeepL and Google
/// Translate. The actions always use `text` exactly
/// as given, so they work the same with furigana on or off. Nothing leaves the
/// app until an item is chosen.
private struct TextActions: ViewModifier {
    let text: String
    @Environment(\.openURL) private var openURL
    @Environment(FormLookupStore.self) private var formLookup: FormLookupStore?
    @Environment(KanjiStore.self) private var kanjiStore: KanjiStore?
    @State private var lookup: FormLookupRequest?
    @State private var kanjiRequest: KanjiSheetRequest?

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button("Copy", systemImage: "doc.on.doc") {
                    Clipboard.copy(text)
                }
                if let url = TextLookupURL.jisho(text) {
                    Button("Open in Jisho", systemImage: "book") {
                        openURL(url)
                    }
                }
                if formLookup?.items(in: text).isEmpty == false {
                    Button("Look up form", systemImage: "text.magnifyingglass") {
                        lookup = FormLookupRequest(text: text)
                    }
                }
                KanjiStrokeMenuItems(characters: kanjiStore?.kanji(in: [text]) ?? []) { kanjiRequest = $0 }
            }
            .formLookupSheet($lookup)
            .kanjiSheet($kanjiRequest)
            .dismissOnLink {
                lookup = nil
                kanjiRequest = nil
            }
    }
}

/// The same menu plus the Translate submenu. Only sentences use this, so only
/// they carry Apple's translation presenter.
private struct TranslatableTextActions: ViewModifier {
    let text: String
    @Environment(\.openURL) private var openURL
    @Environment(FormLookupStore.self) private var formLookup: FormLookupStore?
    @Environment(KanjiStore.self) private var kanjiStore: KanjiStore?
    @State private var lookup: FormLookupRequest?
    @State private var kanjiRequest: KanjiSheetRequest?
    @State private var showingAppleTranslation = false

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button("Copy", systemImage: "doc.on.doc") {
                    Clipboard.copy(text)
                }
                if let url = TextLookupURL.jisho(text) {
                    Button("Open in Jisho", systemImage: "book") {
                        openURL(url)
                    }
                }
                if formLookup?.items(in: text).isEmpty == false {
                    Button("Look up form", systemImage: "text.magnifyingglass") {
                        lookup = FormLookupRequest(text: text)
                    }
                }
                KanjiStrokeMenuItems(characters: kanjiStore?.kanji(in: [text]) ?? []) { kanjiRequest = $0 }
                Menu("Translate", systemImage: "translate") {
                    Button("Apple Translate") {
                        showingAppleTranslation = true
                    }
                    if let url = TextLookupURL.deepL(text) {
                        Button("DeepL") { openURL(url) }
                    }
                    if let url = TextLookupURL.google(text) {
                        Button("Google Translate") { openURL(url) }
                    }
                }
            }
            .translationPresentation(isPresented: $showingAppleTranslation, text: text)
            .formLookupSheet($lookup)
            .kanjiSheet($kanjiRequest)
            .dismissOnLink {
                showingAppleTranslation = false
                lookup = nil
                kanjiRequest = nil
            }
    }
}

/// The text menu's stroke-order items: for one kanji, "Stroke order of 食" and "Practise writing it";
/// for several, a "Stroke order" submenu with one item per kanji. Nothing without kanji data.
private struct KanjiStrokeMenuItems: View {
    let characters: [Character]
    let open: (KanjiSheetRequest) -> Void

    var body: some View {
        if characters.count == 1, let character = characters.first {
            Button("Stroke order of \(String(character))", systemImage: "paintbrush.pointed") {
                open(KanjiSheetRequest(character: character))
            }
            Button("Practise writing it", systemImage: "pencil.and.scribble") {
                open(KanjiSheetRequest(character: character, mode: .trace))
            }
        } else if characters.count > 1 {
            Menu("Stroke order", systemImage: "paintbrush.pointed") {
                ForEach(characters, id: \.self) { character in
                    Button(String(character)) { open(KanjiSheetRequest(character: character)) }
                }
            }
        }
    }
}

extension View {
    /// Adds the text-actions menu for `text`; `translate` adds the Translate
    /// submenu (for sentences). The text is trimmed once here, so every action
    /// sees the same string; blank text gets no menu.
    @ViewBuilder
    func textActions(_ text: String, translate: Bool = false) -> some View {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            self
        } else if translate {
            modifier(TranslatableTextActions(text: trimmed))
        } else {
            modifier(TextActions(text: trimmed))
        }
    }
}
