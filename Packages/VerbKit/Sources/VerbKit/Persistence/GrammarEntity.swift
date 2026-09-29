import Foundation
import SwiftData

@Model
public final class GrammarEntity {
    @Attribute(.unique) public var id: String

    /// Position in the source file, so lessons keep their authored order
    /// (a SwiftData fetch is otherwise unordered).
    public var sortOrder: Int

    // The whole point is stored as JSON `Data`, like `VerbEntity.forms`,
    // which sidesteps SwiftData's struct decomposition (it mishandles
    // custom `CodingKeys` such as `AttachmentRule`'s `word_class`) and
    // means adding a field to `GrammarPoint` needs no store migration.
    private var payload: Data

    public init(_ point: GrammarPoint, sortOrder: Int) {
        self.id = point.id
        self.sortOrder = sortOrder
        self.payload = (try? JSONEncoder().encode(point)) ?? Data()
    }

    /// `nil` if the stored payload can't be decoded by this build (e.g.
    /// cached by a newer app version) — callers skip such rows.
    public func toGrammarPoint() -> GrammarPoint? {
        try? JSONDecoder().decode(GrammarPoint.self, from: payload)
    }
}
