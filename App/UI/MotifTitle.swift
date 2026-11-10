import SwiftUI

extension View {
    /// A tab root's navigation title with the theme's motif beside the large title (iOS, where the
    /// screen has a large title). The bar still draws the screen's `navigationSubtitle` under it,
    /// and the inline title once the large title collapses. `showsMotif` false gives a plain title
    /// (a Word Bank folder below the root). Mac: title only.
    func motifTitle(_ title: String, showsMotif: Bool = true) -> some View {
        modifier(MotifTitle(title: title, showsMotif: showsMotif))
    }
}

private struct MotifTitle: ViewModifier {
    let title: String
    let showsMotif: Bool
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        #if os(iOS)
        if showsMotif {
            content
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .largeTitle) {
                        HStack(alignment: .center) {
                            // 早見表 is Japanese: furigana when it is on.
                            JapaneseText(title)
                                .font(.largeTitle.bold())
                                .foregroundStyle(palette.ink)
                                .accessibilityAddTraits(.isHeader)
                            Spacer(minLength: 8)
                            TitleMotifView()
                        }
                    }
                }
        } else {
            content.navigationTitle(title)
        }
        #else
        content.navigationTitle(title)
        #endif
    }
}
