import SwiftUI

struct FormGroupSection: View {
    let title: String
    let forms: [(String, String)]
    @State private var isExpanded: Bool

    init(title: String, forms: [(String, String)], defaultExpanded: Bool) {
        self.title = title
        self.forms = forms
        _isExpanded = State(initialValue: defaultExpanded)
    }

    var body: some View {
        DisclosureGroup(title, isExpanded: $isExpanded) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(forms, id: \.0) { label, value in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(value)
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.top, 4)
        }
        .font(.subheadline.weight(.semibold))
    }
}
