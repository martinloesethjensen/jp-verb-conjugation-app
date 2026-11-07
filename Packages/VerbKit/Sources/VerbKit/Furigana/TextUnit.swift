/// One drawable piece of a string: plain text, or a base with a reading
/// shown above it.
public struct TextUnit: Equatable, Sendable {
    public var text: String
    /// Hiragana shown above `text`, or `nil` for plain text.
    public var reading: String?
    /// True for closing punctuation that must stay on the same line as the
    /// unit before it (a line never starts with 。 or 、).
    public var glueToPrevious: Bool
    /// True for the part of a sentence to draw bold and underlined: the verb form an example
    /// shows. Set by `TextUnit.emphasizing(_:characters:)`.
    public var isEmphasized: Bool

    public init(text: String, reading: String? = nil, glueToPrevious: Bool = false, isEmphasized: Bool = false) {
        self.text = text
        self.reading = reading
        self.glueToPrevious = glueToPrevious
        self.isEmphasized = isEmphasized
    }
}
