import SwiftUI
import VerbKit

extension VerbType {
    /// How the type reads in the filter chip and the navigation subtitle.
    var filterTitle: String {
        switch self {
        case .irregular: "Irregular"
        case .ru: "Ru-verbs"
        case .u: "U-verbs"
        }
    }
}

/// First chip of the filter row: a menu that picks the verb type. Shows its value, and the
/// chosen outline, once a type is selected.
struct TypeFilterChip: View {
    @Binding var selection: VerbType?

    var body: some View {
        Menu {
            Picker("Type", selection: $selection) {
                Text("All").tag(VerbType?.none)
                ForEach([VerbType.irregular, .ru, .u], id: \.self) { type in
                    Text(type.filterTitle).tag(VerbType?.some(type))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selection?.filterTitle ?? "Type")
                Image(systemName: "chevron.down").font(.caption2.weight(.bold)).accessibilityHidden(true)
            }
            .font(.callout.weight(selection == nil ? .semibold : .bold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .chipBackground(nil)
            .overlay { if selection != nil { Capsule().strokeBorder(Color.primary, lineWidth: 2) } }
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel("Type")
        .accessibilityValue(selection?.filterTitle ?? "All")
    }
}
