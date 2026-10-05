import Foundation

public struct WordBankBackup: Identifiable, Equatable, Sendable {
    public var id: String
    public var url: URL
    public var createdAt: Date
}

/// Full-bank `.wordbank` files, newest three kept. The app takes one before every import
/// and restore, so any of them can be undone.
public final class WordBankBackupStore: @unchecked Sendable {
    private let directory: URL
    private let keeping: Int
    private let now: () -> Date

    public init(directory: URL, keeping: Int = 3, now: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.keeping = max(1, keeping)
        self.now = now
    }

    @discardableResult
    public func backUp(_ snapshot: WordBankSnapshot) throws -> WordBankBackup {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try WordBankArchive(snapshot: snapshot, scope: .everything, exportedAt: now()).encoded()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let base = "Backup \(formatter.string(from: now()))"
        var name = "\(base).wordbank"
        var number = 2
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) {
            name = "\(base) (\(number)).wordbank"
            number += 1
        }
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        for old in backups().dropFirst(keeping) { try? FileManager.default.removeItem(at: old.url) }
        return WordBankBackup(id: name, url: url, createdAt: now())
    }

    public func backups() -> [WordBankBackup] {
        let keys: [URLResourceKey] = [.creationDateKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        return urls.filter { $0.pathExtension == "wordbank" }.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return WordBankBackup(
                id: url.lastPathComponent, url: url,
                createdAt: values?.creationDate ?? values?.contentModificationDate ?? .distantPast
            )
        }
        .sorted { ($0.createdAt, $0.id) > ($1.createdAt, $1.id) }
    }

    public func archive(of backup: WordBankBackup) throws -> WordBankArchive {
        try WordBankArchive.decode(try Data(contentsOf: backup.url))
    }
}
