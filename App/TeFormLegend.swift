import SwiftUI
import VerbKit

struct TeFormLegend: View {
    private let rules: [(TeGroup, String)] = [
        (.tte, "う/つ/る → って"),
        (.nde, "む/ぶ/ぬ → んで"),
        (.ite, "く → いて"),
        (.ide, "ぐ → いで"),
        (.shite, "す → して"),
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(rules, id: \.0) { group, rule in
                    Text(rule)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .accentPill(group.accentColor)
                }
            }
        }
        .listRowSeparator(.hidden)
    }
}
