import Foundation

/// One item an action moved: where it was, and where it is now.
public struct JournalEntry: Codable, Sendable, Hashable {
    public let original: URL
    public let current: URL
    public let fileID: FileFingerprint
}

/// A record of the last action, enough to put every item back.
public struct Journal: Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case rename, trash }

    public let kind: Kind
    public let date: Date
    public let entries: [JournalEntry]

    public init(kind: Kind, date: Date = Date(), entries: [JournalEntry]) {
        self.kind = kind
        self.date = date
        self.entries = entries
    }

    /// Puts items back where they were, newest move first. Renames were made
    /// deepest-first, so going backwards restores a folder's name before the
    /// items inside it, and every recorded path is valid when its turn comes.
    ///
    /// Nothing is moved if it has been touched since: an item that is no
    /// longer where the journal left it, or whose old name is now taken, is
    /// reported and left alone.
    public func undo() -> ActionReport {
        var succeeded = 0
        var failures: [String] = []
        for entry in entries.reversed() {
            let name = entry.current.lastPathComponent
            if let problem = FileActions.checkUnchanged(entry.current, expected: entry.fileID) {
                failures.append("\(name): \(problem.localizedDescription)")
                continue
            }
            do {
                try FileActions.move(entry.current, to: entry.original, fileID: entry.fileID)
                succeeded += 1
            } catch {
                failures.append("\(name): \(error.localizedDescription)")
            }
        }
        return ActionReport(succeeded: succeeded, failures: failures)
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    public static func load(from url: URL) throws -> Journal? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(Journal.self, from: Data(contentsOf: url))
    }
}
