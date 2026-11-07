import SwiftUI

/// A detail page's section heading, optionally with a glyph, and optionally with a trailing view
/// on the right (a muted hint, or a "See all" button).
struct SectionHeader<Trailing: View>: View {
    let title: String
    var systemImage: String?
    let trailing: Trailing
    @Environment(\.palette) private var palette

    init(_ title: String, systemImage: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.systemImage = systemImage
        self.trailing = trailing()
    }

    var body: some View {
        // The trailing view moves under the title when both don't fit on one line (large text),
        // so the title never breaks mid-word.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                label.fixedSize()
                Spacer(minLength: 8)
                trailing.fixedSize()
            }
            VStack(alignment: .leading, spacing: 4) {
                label
                trailing
            }
        }
    }

    private var label: some View {
        Label {
            Text(title)
        } icon: {
            if let systemImage { Image(systemName: systemImage) }
        }
        .font(.title3.weight(.semibold))
        .foregroundStyle(palette.ink)
        .accessibilityAddTraits(.isHeader)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String, systemImage: String? = nil) {
        self.init(title, systemImage: systemImage) { EmptyView() }
    }
}
