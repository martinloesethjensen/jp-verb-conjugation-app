import Foundation

extension UserDefaults {
    static let appGroup = UserDefaults(suiteName: "group.dev.martinloeseth.jpverbconjugation") ?? .standard
}
