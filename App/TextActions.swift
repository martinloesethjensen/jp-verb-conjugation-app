import SwiftUI
import Translation
import VerbKit

/// A long-press (right-click) menu that acts on one piece of Japanese text:
/// Copy and Open in Jisho, and, for sentences, a Translate submenu with Apple
/// Translate, DeepL and Google Translate. The actions always use `text` exactly
/// as given, so they work the same with furigana on or off. Nothing leaves the
/// app until an item is chosen.
private struct TextActions: ViewModifier {
    let text: String
    @Environment(\.openURL) private var openURL

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
            }
    }
}

/// The same menu plus the Translate submenu. Only sentences use this, so only
/// they carry Apple's translation presenter.
private struct TranslatableTextActions: ViewModifier {
    let text: String
    @Environment(\.openURL) private var openURL
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
