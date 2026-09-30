/// One drawable piece of a string: plain text, or a base with a reading
/// shown above it.
public struct TextUnit: Equatable, Sendable {
    public var text: String
    /// Hiragana shown above `text`, or `nil` for plain text.
    public var reading: String?
    /// True for closing punctuation that must stay on the same line as the
    /// unit before it (a line never starts with 。 or 、).
    public var glueToPrevious: Bool

    public init(text: String, reading: String? = nil, glueToPrevious: Bool = false) {
        self.text = text
        self.reading = reading
        self.glueToPrevious = glueToPrevious
    }
}
