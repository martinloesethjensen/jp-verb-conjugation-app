/// Progress through tracing one kanji: which stroke is due and how the last attempt went.
public struct KanjiTraceSession: Equatable, Sendable {
    public let strokeCount: Int
    /// The index of the stroke that is due; equal to `strokeCount` when finished.
    public private(set) var step = 0
    /// The last attempt's verdict; a `tooShort` attempt leaves it as it was.
    public private(set) var lastVerdict: TraceVerdict?

    public init(strokeCount: Int) {
        self.strokeCount = strokeCount
    }

    public var isFinished: Bool { step >= strokeCount }

    public mutating func submit(_ verdict: TraceVerdict) {
        guard !isFinished, verdict != .tooShort else { return }
        lastVerdict = verdict
        if verdict == .accepted { step += 1 }
    }

    public mutating func reset() {
        self = KanjiTraceSession(strokeCount: strokeCount)
    }
}
