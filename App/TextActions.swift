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
    let translate: Bool
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
                if translate {
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
            }
            .translationPresentation(isPresented: $showingAppleTranslation, text: text)
    }
}

extension View {
    /// Adds the text-actions menu for `text`; `translate` adds the Translate
    /// submenu (for sentences).
    func textActions(_ text: String, translate: Bool = false) -> some View {
        modifier(TextActions(text: text, translate: translate))
    }
}
