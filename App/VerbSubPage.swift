import Foundation

/// The pages a verb's "More" card pushes.
enum VerbSubPage: Hashable {
    case potential
    case nDesu
    case auxiliaries
    case advanced
    case lessons

    var title: String {
        switch self {
        case .potential: "Potential"
        case .nDesu: "んです"
        case .auxiliaries: "Auxiliaries"
        case .advanced: "Advanced"
        case .lessons: "Grammar"
        }
    }
}
