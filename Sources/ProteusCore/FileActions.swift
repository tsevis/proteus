import Foundation

public struct ActionReport: Sendable {
    public let succeeded: Int
    public let failures: [String]
}

public enum FileActions {
    /// Renames items deepest-first, so renaming a folder never invalidates
    /// the paths of selected items inside it.
    public static func rename(_ items: [FoundItem], matcher: NameMatcher, replacement: String) -> ActionReport {
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

    /// The name `item` would get, or nil when it would not change.
    public static func plannedName(for item: FoundItem, matcher: NameMatcher, replacement: String) -> String? {
        let newName = matcher.replacing(in: item.name, with: replacement)
        return newName == item.name ? nil : newName
    }

    /// Returns `.success(false)` when the name would not change.
    private static func renameOne(_ item: FoundItem, matcher: NameMatcher, replacement: String) -> Result<Bool, Error> {
        guard let newName = plannedName(for: item, matcher: matcher, replacement: replacement) else {
            return .success(false)
        }
        if let problem = validate(newName, replacing: item.name) { return .failure(problem) }
        if let problem = checkUnchanged(item) { return .failure(problem) }

        let destination = item.url.deletingLastPathComponent().appendingPathComponent(newName)
        // The volume may treat the new name as the same file (a case-only or
        // accent-normalisation change); anything else already there is a clash.
        let occupant = FileScanner.fileID(at: destination)
        let sameFile = occupant != nil && occupant == item.fileID
        if occupant != nil, !sameFile { return .failure(RenameError.alreadyExists(newName)) }
        do {
            if sameFile {
                try moveViaTemporaryName(item.url, to: destination)
            } else {
                try FileManager.default.moveItem(at: item.url, to: destination)
            }
            return .success(true)
        } catch {
            return .failure(error)
        }
    }

    private static func validate(_ newName: String, replacing oldName: String) -> RenameError? {
        if newName.isEmpty || newName.contains("/") || newName == "." || newName == ".." {
            return .invalidName(newName)
        }
        if newName.hasPrefix("."), !oldName.hasPrefix(".") {
            return .wouldHide(newName)
        }
        return nil
    }

    /// Refuses to act when the item has gone, or something else now sits at its path.
    private static func checkUnchanged(_ item: FoundItem) -> RenameError? {
        let current = FileScanner.fileID(at: item.url)
        if current == nil { return .vanished }
        if let expected = item.fileID, current != expected { return .replaced }
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
    public static func trash(_ items: [FoundItem]) -> ActionReport {
        let covered = coveredByFolder(items)
        var succeeded = 0
        var failures: [String] = []
        for item in items where !covered.contains(item.id) {
            if let problem = checkUnchanged(item) {
                failures.append("\(item.name): \(problem.localizedDescription)")
                continue
            }
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

public enum RenameError: LocalizedError {
    case invalidName(String)
    case alreadyExists(String)
    case wouldHide(String)
    case vanished
    case replaced

    public var errorDescription: String? {
        switch self {
        case .invalidName(let name): return "Μη έγκυρο νέο όνομα «\(name)»"
        case .alreadyExists(let name): return "Υπάρχει ήδη «\(name)» στον ίδιο φάκελο"
        case .wouldHide(let name): return "Το «\(name)» αρχίζει με τελεία και θα γινόταν κρυφό"
        case .vanished: return "Δεν υπάρχει πια, έχει μετακινηθεί ή σβηστεί από την αναζήτηση και μετά"
        case .replaced: return "Στη θέση του υπάρχει πλέον άλλο αρχείο. Κάνε ξανά αναζήτηση"
        }
    }
}
