import CoreSpotlight
import UniformTypeIdentifiers
import VerbKit

/// Puts every verb and lesson in Spotlight. A result opens through its `verbtable://` link, which
/// the item's identifier carries, so tapping one takes the same path as a widget link.
enum SpotlightIndexer {
    private static let verbDomain = "verbs"
    private static let lessonDomain = "lessons"

    static func index(verbs: [Verb], grammarPoints: [GrammarPoint]) async {
        var items: [CSSearchableItem] = []
        for verb in verbs {
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = verb.kanji.map { "\(verb.dict) (\($0))" } ?? verb.dict
            attributes.contentDescription = "\(verb.meaning) · \(verb.label)"
            attributes.keywords = [verb.dict, verb.kanji, verb.meaning].compactMap { $0 }
            items.append(CSSearchableItem(
                uniqueIdentifier: Route.verb(verb.id).url.absoluteString,
                domainIdentifier: verbDomain, attributeSet: attributes
            ))
        }
        for point in grammarPoints {
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = point.title
            attributes.contentDescription = point.summary
            items.append(CSSearchableItem(
                uniqueIdentifier: Route.grammar(point.id).url.absoluteString,
                domainIdentifier: lessonDomain, attributeSet: attributes
            ))
        }
        let index = CSSearchableIndex.default()
        // Replace rather than add, so a verb removed from the data leaves Spotlight too.
        try? await index.deleteSearchableItems(withDomainIdentifiers: [verbDomain, lessonDomain])
        try? await index.indexSearchableItems(items)
    }

    /// The link a tapped Spotlight result carries.
    static func url(from activity: NSUserActivity) -> URL? {
        (activity.userInfo?[CSSearchableItemActivityIdentifier] as? String).flatMap(URL.init(string:))
    }
}
