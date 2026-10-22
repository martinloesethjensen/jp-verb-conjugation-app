import Foundation
import SwiftData

@Model
public final class TextbookEntity {
    @Attribute(.unique) public var id: String

    /// Position in the source file, so books keep their authored order
    /// (a SwiftData fetch is otherwise unordered).
    public var sortOrder: Int

    // Stored as JSON `Data`, like `GrammarEntity`, so adding a field to
    // `Textbook` needs no store migration.
    private var payload: Data

    public init(_ book: Textbook, sortOrder: Int) {
        self.id = book.id
        self.sortOrder = sortOrder
        self.payload = (try? JSONEncoder().encode(book)) ?? Data()
    }

    /// `nil` if the stored payload can't be decoded by this build; callers skip such rows.
    public func toTextbook() -> Textbook? {
        try? JSONDecoder().decode(Textbook.self, from: payload)
    }
}
