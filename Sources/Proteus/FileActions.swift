import Foundation

struct ActionReport: Sendable {
    let succeeded: Int
    let failures: [String]
}

enum FileActions {
    /// Renames items deepest-first, so renaming a folder never invalidates
    /// the paths of selected items inside it.
    static func rename(_ items: [FoundItem], matcher: NameMatcher, replacement: String) -> ActionReport {
        let ordered = items.sorted { $0.depth > $1.depth }
        var succeeded = 0
        var failures: [String] = []
        for item in ordered {
            switch renameOne(item, matcher: matcher, replacement: replacement) {
            case .success(true): succeeded += 1
            case .success(false): break
            case .failure(let error): failures.append("\(item.name): \(error.localizedDescription)")
            }
        }
        return ActionReport(succeeded: succeeded, failures: failures)
    }

    /// Returns `.success(false)` when the name would not change.
    private static func renameOne(_ item: FoundItem, matcher: NameMatcher, replacement: String) -> Result<Bool, Error> {
        let newName = matcher.replacing(in: item.name, with: replacement)
        guard newName != item.name else { return .success(false) }
        guard !newName.isEmpty, !newName.contains("/"), newName != ".", newName != ".." else {
            return .failure(RenameError.invalidName(newName))
        }
        let destination = item.url.deletingLastPathComponent().appendingPathComponent(newName)
        let caseOnly = newName.lowercased() == item.name.lowercased()
        let fm = FileManager.default
        if !caseOnly, fm.fileExists(atPath: destination.path) {
            return .failure(RenameError.alreadyExists(newName))
        }
        do {
            if caseOnly {
                // Case-insensitive volumes need a detour through a temporary name.
                let temp = item.url.deletingLastPathComponent()
                    .appendingPathComponent(".renaming-\(UUID().uuidString)")
                try fm.moveItem(at: item.url, to: temp)
                try fm.moveItem(at: temp, to: destination)
            } else {
                try fm.moveItem(at: item.url, to: destination)
            }
            return .success(true)
        } catch {
            return .failure(error)
        }
    }

    /// Moves items to the Trash (recoverable). Items inside another selected
    /// folder are skipped, since they go to the Trash with that folder.
    static func trash(_ items: [FoundItem]) -> ActionReport {
        let folderPaths = Set(items.filter(\.isDirectory).map { $0.url.path + "/" })
        let topLevel = items.filter { item in
            !folderPaths.contains { item.url.path.hasPrefix($0) }
        }
        var succeeded = 0
        var failures: [String] = []
        for item in topLevel {
            do {
                try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                succeeded += 1
            } catch {
                failures.append("\(item.name): \(error.localizedDescription)")
            }
        }
        return ActionReport(succeeded: succeeded, failures: failures)
    }
}

enum RenameError: LocalizedError {
    case invalidName(String)
    case alreadyExists(String)

    var errorDescription: String? {
        switch self {
        case .invalidName(let name): return "Μη έγκυρο νέο όνομα «\(name)»"
        case .alreadyExists(let name): return "Υπάρχει ήδη «\(name)» στον ίδιο φάκελο"
        }
    }
}
