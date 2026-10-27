import CoreSpotlight
import UniformTypeIdentifiers
import VerbKit

/// Puts every verb and lesson in Spotlight. A result opens through its `verbtable://` link, which
/// the item's identifier carries, so tapping one takes the same path as a widget link.
enum SpotlightIndexer {
    private static let verbDomain = "verbs"
    private static let lessonDomain = "lessons"
    private static let counterDomain = "counters"
    private static let counterGroupDomain = "counterGroups"

    static func index(
        verbs: [Verb], grammarPoints: [GrammarPoint], counters: [Counter] = [], groups: [CounterGroup] = []
    ) async {
        var items: [CSSearchableItem] = []
        for verb in verbs {
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = verb.displayTitle
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
        for counter in counters {
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = "\(counter.counter) (\(counter.reading))"
            let primary = counter.thingsByFit.filter { $0.fit == .primary }.map(\.meaning).prefix(4)
            attributes.contentDescription = ([counter.meaning] + primary).joined(separator: " · ")
            // The counter, its readings, everything it counts, and every preferred counted form (さんぼん).
            attributes.keywords = [counter.counter, counter.reading, counter.meaning]
                + counter.things.flatMap { [$0.word, $0.kana, $0.meaning] }
                + CounterNumber.allCases.compactMap { counter.readings(for: $0).first }
            items.append(CSSearchableItem(
                uniqueIdentifier: Route.counter(counter.id).url.absoluteString,
                domainIdentifier: counterDomain, attributeSet: attributes
            ))
        }
        let byID = Dictionary(counters.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for group in groups {
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = group.title
            attributes.contentDescription = group.members.compactMap { byID[$0.counter]?.counter }
                .joined(separator: " · ")
            items.append(CSSearchableItem(
                uniqueIdentifier: Route.counterGroup(group.id).url.absoluteString,
                domainIdentifier: counterGroupDomain, attributeSet: attributes
            ))
        }
        let index = CSSearchableIndex.default()
        // Replace rather than add, so a verb removed from the data leaves Spotlight too.
        try? await index.deleteSearchableItems(withDomainIdentifiers: [verbDomain, lessonDomain, counterDomain, counterGroupDomain])
        try? await index.indexSearchableItems(items)
    }

    /// The link a tapped Spotlight result carries.
    static func url(from activity: NSUserActivity) -> URL? {
        (activity.userInfo?[CSSearchableItemActivityIdentifier] as? String).flatMap(URL.init(string:))
    }
}
