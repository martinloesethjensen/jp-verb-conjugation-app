import SwiftUI
import VerbKit

/// One conjugated form in a table. The part shared with the dictionary form is
/// muted and the part that changed is bold ink, with no colour so nothing reads
/// as a link. A form identical to the dictionary form is drawn normally.
struct FormCell: View {
    let form: String
    let dict: String
    @Environment(\.palette) private var palette

    var body: some View {
        let split = FormSplit.split(form, from: dict)
        Group {
            if split.hasEnding {
                Text("\(Text(split.stem).fontWeight(.regular).foregroundStyle(palette.muted))\(Text(split.ending).fontWeight(.bold).foregroundStyle(palette.ink))")
            } else {
                Text(form).foregroundStyle(palette.ink)
            }
        }
        // Wrap rather than shrink or truncate: long forms stay whole at the reader's text size.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .speakOnTap(form)
        .textActions(form)
    }
}
