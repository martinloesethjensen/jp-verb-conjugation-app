import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let wordBank = UTType(exportedAs: "dev.martinloeseth.jpverbconjugation.wordbank", conformingTo: .json)
}

/// For `fileExporter`: the bytes of a `.wordbank` file.
struct WordBankFile: FileDocument {
    static var readableContentTypes: [UTType] { [.wordBank] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
