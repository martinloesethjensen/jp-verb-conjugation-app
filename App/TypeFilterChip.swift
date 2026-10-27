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
            FilterChip(selection?.filterTitle ?? "Type", isOn: selection != nil, showsChevron: true)
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel("Type")
        .accessibilityValue(selection?.filterTitle ?? "All")
    }
}
