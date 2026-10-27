/// A trie of surfaces by Unicode scalar, each surface carrying a list of hits. Walking it
/// from a position in a text finds every surface that starts there in one pass, so a
/// lookup costs the length of the longest surface, not the number of surfaces.
///
/// The edges live in one flat dictionary keyed by (node, scalar) rather than a dictionary
/// per node, which keeps the memory near one small entry per edge at 100k+ surfaces.
struct SurfaceTrie<Hit: Hashable & Sendable>: Sendable {
    struct Entry: Sendable {
        let surface: String
        var hits: [Hit]
    }

    /// A surface found in a text: where it ends and which entry it is.
    struct Prefix {
        let end: String.Index
        let entry: Int
    }

    private var edges: [UInt64: Int32] = [:]
    /// The entry each node completes, or -1. Node 0 is the root.
    private var terminals: [Int32] = [-1]
    private(set) var entries: [Entry] = []

    var nodeCount: Int { terminals.count }

    private static func key(_ node: Int32, _ scalar: Unicode.Scalar) -> UInt64 {
        UInt64(UInt32(bitPattern: node)) << 32 | UInt64(scalar.value)
    }

    /// Adds `hit` to `surface`'s list, once.
    mutating func insert(_ surface: String, _ hit: Hit) {
        var node: Int32 = 0
        for scalar in surface.unicodeScalars {
            let key = Self.key(node, scalar)
            if let child = edges[key] {
                node = child
            } else {
                let child = Int32(terminals.count)
                terminals.append(-1)
                edges[key] = child
                node = child
            }
        }
        let entry = terminals[Int(node)]
        if entry < 0 {
            terminals[Int(node)] = Int32(entries.count)
            entries.append(Entry(surface: surface, hits: [hit]))
        } else if !entries[Int(entry)].hits.contains(hit) {
            entries[Int(entry)].hits.append(hit)
        }
    }

    /// The hits for exactly `surface`; empty when it isn't one.
    func hits(for surface: some StringProtocol) -> [Hit] {
        var node: Int32 = 0
        for scalar in surface.unicodeScalars {
            guard let child = edges[Self.key(node, scalar)] else { return [] }
            node = child
        }
        let entry = terminals[Int(node)]
        return entry < 0 ? [] : entries[Int(entry)].hits
    }

    /// Every surface that `text` has at `start`, longest first.
    func prefixes(of text: String, from start: String.Index) -> [Prefix] {
        var found: [Prefix] = []
        var node: Int32 = 0
        let scalars = text.unicodeScalars
        var index = start
        while index < scalars.endIndex, let child = edges[Self.key(node, scalars[index])] {
            node = child
            index = scalars.index(after: index)
            let entry = terminals[Int(node)]
            if entry >= 0 { found.append(Prefix(end: index, entry: Int(entry))) }
        }
        return found.reversed()
    }
}
