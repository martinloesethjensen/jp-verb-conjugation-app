import SwiftUI
import VerbKit

/// Single-select chips that filter the list by て-form group. Tapping the chosen
/// chip again goes back to All.
struct TeFormFilter: View {
    @Binding var selection: TeGroup?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", accent: nil, isOn: selection == nil) { selection = nil }
                ForEach(TeFormRule.all, id: \.group) { rule in
                    chip(rule.result, accent: rule.group.accentColor, isOn: selection == rule.group) {
                        selection = selection == rule.group ? nil : rule.group
                    }
                }
            }
        }
        // Full width, so chips scroll edge to edge; the content margin keeps the
        // first and last chip off the screen edge when scrolled to either end.
        .contentMargins(.horizontal, 20, for: .scrollContent)
    }

    private func chip(_ title: String, accent: Color?, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(isOn ? .bold : .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .chipBackground(accent)
                .overlay { if isOn { Capsule().strokeBorder(Color.primary, lineWidth: 2) } }
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    @ViewBuilder func chipBackground(_ accent: Color?) -> some View {
        if let accent {
            accentPill(accent)
        } else {
            foregroundStyle(.primary).glassEffect(.regular, in: Capsule())
        }
    }
}
