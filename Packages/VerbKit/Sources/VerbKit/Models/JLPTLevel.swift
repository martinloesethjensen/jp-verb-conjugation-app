public enum JLPTLevel: String, Codable, CaseIterable, Hashable, Sendable, Comparable {
    case n5 = "N5", n4 = "N4", n3 = "N3", n2 = "N2", n1 = "N1"

    /// N5 (easiest) sorts first.
    public static func < (lhs: JLPTLevel, rhs: JLPTLevel) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}
