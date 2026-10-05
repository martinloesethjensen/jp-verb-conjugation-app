import SwiftUI
import VerbKit

/// One entry. Filled out in Task 9.
struct WordBankDetailView: View {
    let entry: WordBankEntryValue
    @Binding var selection: UUID?

    var body: some View {
        Text(entry.text)
    }
}
