import Foundation
import SwiftData

@Model
public final class VerbEntity {
    @Attribute(.unique) public var dict: String
    public var type: String
    public var label: String
    public var kanji: String?
    public var meaning: String
    public var verbDescription: String
    public var notes: String?
    public var teGroup: String?
    /// JLPT level raw value ("N5"…"N1"); nil when the verb has none. The default
    /// lets rows saved before this existed migrate.
    public var jlpt: String? = nil
    /// Position in the source file, so the list keeps its authored order (a
    /// SwiftData fetch is otherwise unordered). The default lets rows saved before
    /// this existed migrate; the next sync rewrites them with real positions.
    public var sortOrder: Int = 0

    // `forms`/`examples` are stored as JSON `Data` rather than as native
    // `VerbForms`/`[VerbExample]` attributes. In this SwiftData build,
    // automatic struct decomposition ("composite attributes") does not
    // correctly honor a type's custom `CodingKeys` — and `VerbForms` has
    // one, to match the API's snake_case field names — which corrupts the
    // stored row on save (confirmed with a minimal repro: a 2-field struct
    // with a renaming `CodingKeys` fails identically; the same struct
    // without custom `CodingKeys` persists fine). Encoding to `Data`
    // ourselves sidesteps SwiftData's decomposition entirely and keeps the
    // public `forms`/`examples` properties working exactly as before.
    private var formsData: Data
    private var examplesData: Data

    public var forms: VerbForms {
        get {
            if let decoded = try? JSONDecoder().decode(VerbForms.self, from: formsData) {
                return decoded
            }
            assertionFailure("VerbEntity.forms failed to decode formsData for dict=\(dict)")
            return .empty
        }
        set {
            formsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    public var examples: [VerbExample] {
        get {
            if let decoded = try? JSONDecoder().decode([VerbExample].self, from: examplesData) {
                return decoded
            }
            assertionFailure("VerbEntity.examples failed to decode examplesData for dict=\(dict)")
            return []
        }
        set {
            examplesData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    public init(
        dict: String,
        type: String,
        label: String,
        kanji: String?,
        meaning: String,
        verbDescription: String,
        notes: String?,
        teGroup: String?,
        jlpt: String? = nil,
        forms: VerbForms,
        examples: [VerbExample],
        sortOrder: Int = 0
    ) {
        self.sortOrder = sortOrder
        self.dict = dict
        self.type = type
        self.label = label
        self.kanji = kanji
        self.meaning = meaning
        self.verbDescription = verbDescription
        self.notes = notes
        self.teGroup = teGroup
        self.jlpt = jlpt
        self.formsData = (try? JSONEncoder().encode(forms)) ?? Data()
        self.examplesData = (try? JSONEncoder().encode(examples)) ?? Data()
    }
}

private extension VerbForms {
    /// Fallback used only if `formsData` somehow fails to decode (should
    /// never happen since we always write it via `JSONEncoder` ourselves).
    static var empty: VerbForms {
        VerbForms(
            masuPos: "", masuNeg: "", masuPast: "", masuPastNeg: "",
            te: "", shortPos: "", shortNeg: "", shortPast: "", shortPastNeg: ""
        )
    }
}

public extension VerbEntity {
    convenience init(_ verb: Verb, sortOrder: Int = 0) {
        self.init(
            dict: verb.dict,
            type: verb.type.rawValue,
            label: verb.label,
            kanji: verb.kanji,
            meaning: verb.meaning,
            verbDescription: verb.description,
            notes: verb.notes,
            teGroup: verb.teGroup?.rawValue,
            jlpt: verb.jlpt?.rawValue,
            forms: verb.forms,
            examples: verb.examples,
            sortOrder: sortOrder
        )
    }

    /// `nil` if `type`/`teGroup` hold a raw value this build's enums
    /// don't recognize (e.g. old cached data from a newer app version) —
    /// callers skip such entities rather than crash.
    func toVerb() -> Verb? {
        guard let verbType = VerbType(rawValue: type) else { return nil }
        let resolvedTeGroup = teGroup.flatMap { TeGroup(rawValue: $0) }
        return Verb(
            type: verbType,
            label: label,
            dict: dict,
            kanji: kanji,
            meaning: meaning,
            description: verbDescription,
            notes: notes,
            teGroup: resolvedTeGroup,
            jlpt: jlpt.flatMap { JLPTLevel(rawValue: $0) },
            forms: forms,
            examples: examples
        )
    }
}
