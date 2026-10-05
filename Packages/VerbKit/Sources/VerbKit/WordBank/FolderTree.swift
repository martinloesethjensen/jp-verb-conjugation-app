import Foundation

/// Read-only questions about the folder hierarchy. Folders nest without limit;
/// sibling names are unique under `JapaneseNormalizer.key`, so a path names
/// exactly one folder.
public struct FolderTree: Sendable {
    private let byID: [UUID: WordBankFolderValue]
    private let childrenByParent: [UUID?: [WordBankFolderValue]]

    public init(_ folders: [WordBankFolderValue]) {
        byID = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        childrenByParent = Dictionary(grouping: folders, by: \.parentID).mapValues { siblings in
            siblings.sorted {
                ($0.sortOrder, JapaneseNormalizer.key($0.name)) < ($1.sortOrder, JapaneseNormalizer.key($1.name))
            }
        }
    }

    public func folder(_ id: UUID) -> WordBankFolderValue? { byID[id] }

    /// Top-level folders for `nil`. Sorted by sort order, then name.
    public func children(of id: UUID?) -> [WordBankFolderValue] {
        childrenByParent[id] ?? []
    }

    /// Every folder below `id`, at any depth; not `id` itself.
    public func descendants(of id: UUID) -> Set<UUID> {
        var found = Set<UUID>()
        var queue = children(of: id).map(\.id)
        while let next = queue.popLast() {
            guard found.insert(next).inserted, next != id else { continue }
            queue += children(of: next).map(\.id)
        }
        found.remove(id)
        return found
    }

    /// From the top-level folder down to `id`. Stops at a cycle in bad data.
    public func path(of id: UUID) -> [WordBankFolderValue] {
        var path: [WordBankFolderValue] = []
        var seen = Set<UUID>()
        var current = byID[id]
        while let folder = current, seen.insert(folder.id).inserted {
            path.insert(folder, at: 0)
            current = folder.parentID.flatMap { byID[$0] }
        }
        return path
    }

    /// To the top level always; otherwise into an existing folder that is neither
    /// the folder itself nor one of its descendants.
    public func canMove(_ id: UUID, to parent: UUID?) -> Bool {
        guard let parent else { return true }
        return byID[parent] != nil && parent != id && !descendants(of: id).contains(parent)
    }

    public func nameIsFree(_ name: String, in parent: UUID?, ignoring: UUID? = nil) -> Bool {
        let key = JapaneseNormalizer.key(name)
        return !children(of: parent).contains { $0.id != ignoring && JapaneseNormalizer.key($0.name) == key }
    }
}
