import SwiftUI
import VerbKit

/// The scope chips, shown before typing and above results.
struct SearchScopeChips: View {
    @Binding var scope: SearchScope

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchScope.allCases, id: \.self) { option in
                    Button {
                        scope = option
                    } label: {
                        FilterChip(SearchDisplay.title(option), isOn: scope == option)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(scope == option ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollClipDisabled()
    }
}

/// Before typing: the title, the scope chips, recent searches and how a query can be typed.
struct SearchEmptyState: View {
    @Binding var scope: SearchScope
    let recents: [String]
    let onPick: (String) -> Void
    let onClear: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Search")
                        .font(.largeTitle.bold())
                        .foregroundStyle(palette.ink)
                    JapaneseText("検索")
                        .font(.headword(.title3))
                        .foregroundStyle(palette.muted)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 16)
                .accessibilityAddTraits(.isHeader)

                SearchScopeChips(scope: $scope)

                if !recents.isEmpty { recentSection }
                anyWaySection
            }
            .padding(.vertical, 12)
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Recent") {
                Button("Clear", action: onClear)
                    .font(.subheadline)
                    .foregroundStyle(palette.muted)
            }
            WrappingFlowLayout(spacing: 8) {
                ForEach(recents, id: \.self) { recent in
                    Button {
                        onPick(recent)
                    } label: {
                        Label {
                            Text(recent).foregroundStyle(palette.ink)
                        } icon: {
                            Image(systemName: "clock").foregroundStyle(palette.muted)
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(palette.card, in: Capsule())
                        .overlay(Capsule().stroke(palette.rule, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var anyWaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Type it any way")
            VStack(spacing: 0) {
                row("Romaji") { Text("**nomu** → のむ") }
                Divider().overlay(palette.rule)
                row("Kana or kanji") { JapaneseText("飲む · のむ · ノム") }
                Divider().overlay(palette.rule)
                row("English") { Text("drink") }
                Divider().overlay(palette.rule)
                row("A form") { JapaneseText("のんだ → 飲む") }
            }
            .paperCard(cornerRadius: 14)
        }
        .padding(.horizontal, 16)
    }

    private func row(_ label: String, @ViewBuilder value: () -> some View) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(label).foregroundStyle(palette.muted)
                Spacer(minLength: 12)
                value().foregroundStyle(palette.ink)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label).foregroundStyle(palette.muted)
                value().foregroundStyle(palette.ink)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}
