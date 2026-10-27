import Foundation

public struct ActionReport: Sendable {
    public let succeeded: Int
    public let failures: [String]
}

/// What an action did, and how to take it back.
public struct ActionOutcome: Sendable {
    public let report: ActionReport
    public let journal: Journal
}

public enum FileActions {
    /// Renames by find and replace: a shortcut through the planner, used by tests and scripts.
    public static func rename(_ items: [FoundItem], matcher: NameMatcher, replacement: String) -> ActionReport {
        let proposals = items.map { (item: $0, name: matcher.replacing(in: $0.name, with: replacement)) }
        let steps = RenamePlanner.plan(proposals, numberClashes: false)
        let blocked = steps.compactMap { step in step.problem.map { "\(step.item.name): \($0.localizedDescription)" } }
        let outcome = apply(steps)
        return ActionReport(succeeded: outcome.report.succeeded, failures: blocked + outcome.report.failures)
    }

    /// Carries out the changing steps of a plan, deepest first, so renaming a
    /// folder never invalidates the paths of selected items inside it. Every
    /// check is made again against the disk as it is now.
    public static func apply(_ steps: [RenameStep]) -> ActionOutcome {
        let ordered = steps.filter(\.isChange).sorted { $0.item.depth > $1.item.depth }
        var succeeded = 0
        var failures: [String] = []
        var entries: [JournalEntry] = []
        for step in ordered {
            switch renameOne(step.item, to: step.newName) {
            case .success(let destination):
                succeeded += 1
                if let fileID = step.item.fileID {
                    entries.append(JournalEntry(original: step.item.url, current: destination, fileID: fileID))
                }
            case .failure(let error):
                failures.append("\(step.item.name): \(error.localizedDescription)")
            }
        }
        return ActionOutcome(report: ActionReport(succeeded: succeeded, failures: failures),
                             journal: Journal(kind: .rename, entries: entries))
    }

    private static func renameOne(_ item: FoundItem, to newName: String) -> Result<URL, Error> {
        if let problem = RenamePlanner.validate(newName, replacing: item.name) { return .failure(problem) }
        if let problem = checkUnchanged(item.url, expected: item.fileID) { return .failure(problem) }
        let destination = item.url.deletingLastPathComponent().appendingPathComponent(newName)
        do {
            try move(item.url, to: destination, fileID: item.fileID)
            return .success(destination)
        } catch {
            return .failure(error)
        }
    }

    /// Moves without ever replacing anything. The volume may treat the new
    /// name as the same file (a case-only or accent-normalisation change);
    /// anything else already there is a clash.
    static func move(_ source: URL, to destination: URL, fileID: FileFingerprint?) throws {
        let occupant = FileScanner.fileID(at: destination)
        let sameFile = occupant != nil && occupant == fileID
        if occupant != nil, !sameFile { throw RenameError.alreadyExists(destination.lastPathComponent) }
        if sameFile {
            try moveViaTemporaryName(source, to: destination)
        } else {
            try FileManager.default.moveItem(at: source, to: destination)
        }
    }

    /// Refuses to act when the item has gone, or something else now sits at its path.
    static func checkUnchanged(_ url: URL, expected: FileFingerprint?) -> RenameError? {
        let current = FileScanner.fileID(at: url)
        if current == nil { return .vanished }
        if let expected, current != expected { return .replaced }
        return nil
    }

    /// Case-insensitive volumes need a detour through a temporary name. If the
    /// second step fails, the item is put back under its original name.
    private static func moveViaTemporaryName(_ source: URL, to destination: URL) throws {
        let fm = FileManager.default
        let temp = source.deletingLastPathComponent()
            .appendingPathComponent(".proteus-renaming-\(UUID().uuidString)")
        try fm.moveItem(at: source, to: temp)
        do {
            try fm.moveItem(at: temp, to: destination)
        } catch {
            try? fm.moveItem(at: temp, to: source)
            throw error
        }
    }

    /// Items inside another selected folder: they go to the Trash with it.
    public static func coveredByFolder(_ items: [FoundItem]) -> Set<String> {
        let folderPaths = items.filter(\.isDirectory).map { $0.url.path + "/" }
        return Set(items.filter { item in folderPaths.contains { item.url.path.hasPrefix($0) } }.map(\.id))
    }

    /// Moves items to the Trash (recoverable). Items inside another selected
    /// folder are skipped, since they go to the Trash with that folder.
    public static func trash(_ items: [FoundItem]) -> ActionOutcome {
        let covered = coveredByFolder(items)
        var succeeded = 0
        var failures: [String] = []
        var entries: [JournalEntry] = []
        for item in items where !covered.contains(item.id) {
            if let problem = checkUnchanged(item.url, expected: item.fileID) {
                failures.append("\(item.name): \(problem.localizedDescription)")
                continue
            }
            do {
                var inTrash: NSURL?
                try FileManager.default.trashItem(at: item.url, resultingItemURL: &inTrash)
                succeeded += 1
                if let inTrash = inTrash as URL?, let fileID = item.fileID {
                    entries.append(JournalEntry(original: item.url, current: inTrash, fileID: fileID))
                }
            } catch {
                failures.append("\(item.name): \(error.localizedDescription)")
            }
        }
        return ActionOutcome(report: ActionReport(succeeded: succeeded, failures: failures),
                             journal: Journal(kind: .trash, entries: entries))
    }
}
