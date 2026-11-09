import Foundation

/// A lesson's forms side by side: the i-th polite form beside the i-th casual one.
public enum ConjugationTable {
    /// Formal forms count as polite, after the polite ones; the shorter column is padded with nil.
    public static func rows(_ conjugations: [GrammarConjugation]) -> [(polite: GrammarConjugation?, casual: GrammarConjugation?)] {
        let polite = conjugations.filter { $0.register == .polite } + conjugations.filter { $0.register == .formal }
        let casual = conjugations.filter { $0.register == .casual }
        return (0..<max(polite.count, casual.count)).map { index in
            (polite.indices.contains(index) ? polite[index] : nil, casual.indices.contains(index) ? casual[index] : nil)
        }
    }
}
