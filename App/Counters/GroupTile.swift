import SwiftUI
import VerbKit

/// One tile of the groups grid: the group's symbol, its title and its counters (杯 · 本 · つ).
struct GroupTile: View {
    let title: String
    let symbol: String
    let counters: String
    let spokenCounters: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(.tint)
                Spacer(minLength: 0)
                Text(title)
                    .font(.headline)
                Text(counters)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            .padding(14)
            .glassEffect(in: RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(spokenCounters)")
        .accessibilityAddTraits(.isButton)
    }
}
