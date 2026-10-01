/// A conjugated form split into the part it shares with the dictionary form (the
/// stem) and the part that changed (the ending). The verb page shows the stem in
/// grey and the ending in bold.
public struct FormSplit: Equatable, Sendable {
    public let stem: String
    public let ending: String

    public init(stem: String, ending: String) {
        self.stem = stem
        self.ending = ending
    }

    /// True when something changed, so the cell has an ending to emphasise.
    /// A form identical to the dictionary form has none.
    public var hasEnding: Bool { !ending.isEmpty }

    /// The longest common prefix of `form` and `dict` is the stem and the rest of
    /// `form` is the ending. No shared prefix (くる → きます) makes the whole form
    /// the ending; an identical form (たべる → たべる) has an empty ending.
    public static func split(_ form: String, from dict: String) -> FormSplit {
        var shared = 0
        for (a, b) in zip(form, dict) {
            guard a == b else { break }
            shared += 1
        }
        return FormSplit(stem: String(form.prefix(shared)), ending: String(form.dropFirst(shared)))
    }
}
