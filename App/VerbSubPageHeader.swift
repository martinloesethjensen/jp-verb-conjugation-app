import SwiftUI
import VerbKit

/// The top of a verb sub-page: the verb small and muted for context, the page title large, and
/// optionally the page's headline form in Mincho with furigana (食べられる on Potential).
struct VerbSubPageHeader: View {
    let verb: Verb
    let title: String
    var headline: String?
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            JapaneseText(units: verb.dictionaryUnits)
                .font(.headword(.subheadline))
                .foregroundStyle(palette.muted)
            Text(title)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(palette.ink)
                .accessibilityAddTraits(.isHeader)
            if let headline {
                JapaneseText(units: verb.units(for: headline))
                    .font(.headword(.largeTitle, scale: 1.3))
                    .foregroundStyle(palette.ink)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// A verb sub-page's surroundings: the paper behind it, and on iOS the navigation title
    /// hidden because `VerbSubPageHeader` shows it. The title stays set for the back button
    /// and VoiceOver.
    func verbSubPage(title: String) -> some View {
        self
            .paperBackground()
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            #endif
    }
}
