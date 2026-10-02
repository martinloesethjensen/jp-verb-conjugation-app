import SwiftUI
import VerbKit

/// One conjugated form in a table. The part shared with the dictionary form is
/// light grey and the part that changed is bold, with no colour so nothing reads
/// as a link. A form identical to the dictionary form is drawn normally.
struct FormCell: View {
    let form: String
    let dict: String

    var body: some View {
        let split = FormSplit.split(form, from: dict)
        Group {
            if split.hasEnding {
                Text("\(Text(split.stem).fontWeight(.regular).foregroundStyle(.secondary))\(Text(split.ending).fontWeight(.bold).foregroundStyle(.primary))")
            } else {
                Text(form)
            }
        }
        // Wrap rather than shrink: long forms stay at the reader's text size.
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .speakOnTap(form)
        .textActions(form)
    }
}
