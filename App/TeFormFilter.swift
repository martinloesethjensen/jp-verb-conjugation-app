import SwiftUI
import VerbKit

/// Filter chips: a Type menu, then single-select て-form groups. Tapping the chosen
/// group again goes back to All.
struct TeFormFilter: View {
    @Binding var type: VerbType?
    @Binding var selection: TeGroup?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                TypeFilterChip(selection: $type)
                chip("All", accent: nil, isOn: selection == nil) { selection = nil }
                ForEach(TeFormRule.all, id: \.group) { rule in
                    chip(rule.result, accent: rule.group.accentColor, isOn: selection == rule.group) {
                        selection = selection == rule.group ? nil : rule.group
                    }
                }
            }
            // Padding inside the scrolling content, so only the first and last chip
            // are inset; the scroll view itself spans the full width and never clips.
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    private func chip(_ title: String, accent: Color?, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            FilterChip(title, accent: accent, isOn: isOn)
        }
        .buttonStyle(.plain)
    }
}
