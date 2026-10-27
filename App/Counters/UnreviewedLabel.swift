import SwiftUI

/// The small mark on numbers above 10. Their readings are generated and checked by the pipeline but no
/// teacher has read them, so they carry the same "unreviewed" text as the textbook lesson mappings.
struct UnreviewedLabel: View {
    var body: some View {
        Text("unreviewed")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}
