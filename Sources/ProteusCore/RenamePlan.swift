import Foundation

/// What renaming one item will do, worked out before anything is touched.
public struct RenameStep: Sendable, Identifiable, Hashable {
    public let item: FoundItem
    /// The name the item will get, including any number added to avoid a clash.
    public let newName: String
    /// Why it will not be renamed, if it will not.
    public let problem: RenameError?
    /// True when " 2", " 3"… was added so two items would not share a name.
    public let numbered: Bool

    public var id: String { item.id }
    public var isChange: Bool { problem == nil && newName != item.name }
}

/// Turns proposed names into a plan the table can show and the rename can follow.
///
/// Pure apart from looking up what already sits at each destination, so it can
/// run on every keystroke. Every name it reports is the name the item will
/// actually get; every item it will not rename says why.
public enum RenamePlanner {
    public static let maxNameBytes = 255

    public static func plan(_ proposals: [(item: FoundItem, name: String)], numberClashes: Bool,
                            occupant: (URL) -> FileFingerprint? = FileScanner.fileID) -> [RenameStep] {
        // Names are compared ignoring case and normalisation: on a standard
        // Mac volume `Pete.txt` and `pete.txt` are the same file.
        func key(_ item: FoundItem, _ name: String) -> String {
            item.url.deletingLastPathComponent().path + "/" + name.precomposedStringWithCanonicalMapping.lowercased()
        }

        var claimed = Set<String>()
        var steps = [RenameStep?](repeating: nil, count: proposals.count)

        // Items that keep their name (or change only its case) hold it first,
        // so nothing else in the batch is promised that name.
        for (index, proposal) in proposals.enumerated() where key(proposal.item, proposal.name) == key(proposal.item, proposal.item.name) {
            claimed.insert(key(proposal.item, proposal.item.name))
            let problem = proposal.name == proposal.item.name ? nil : validate(proposal.name, replacing: proposal.item.name)
            steps[index] = RenameStep(item: proposal.item, newName: proposal.name, problem: problem, numbered: false)
        }

        for (index, proposal) in proposals.enumerated() where steps[index] == nil {
            let item = proposal.item
            if let problem = validate(proposal.name, replacing: item.name) {
                steps[index] = RenameStep(item: item, newName: proposal.name, problem: problem, numbered: false)
                continue
            }
            func isTaken(_ name: String) -> Bool {
                if claimed.contains(key(item, name)) { return true }
                let found = occupant(item.url.deletingLastPathComponent().appendingPathComponent(name))
                return found != nil && found != item.fileID
            }
            var name = proposal.name
            var numbered = false
            if isTaken(name) {
                guard numberClashes, let free = firstFreeName(after: name, item: item, isTaken: isTaken) else {
                    let problem: RenameError = claimed.contains(key(item, name)) ? .duplicateInBatch(name) : .alreadyExists(name)
                    steps[index] = RenameStep(item: item, newName: name, problem: problem, numbered: false)
                    continue
                }
                name = free
                numbered = true
            }
            claimed.insert(key(item, name))
            steps[index] = RenameStep(item: item, newName: name, problem: nil, numbered: numbered)
        }
        return steps.compactMap { $0 }
    }

    static func firstFreeName(after name: String, item: FoundItem, isTaken: (String) -> Bool) -> String? {
        let parts = NameParts(name, isDirectory: item.isDirectory)
        for counter in 2...10_000 {
            let candidate = NameParts.join("\(parts.stem) \(counter)", parts.ext)
            if candidate.utf8.count > maxNameBytes { return nil }
            if !isTaken(candidate) { return candidate }
        }
        return nil
    }

    static func validate(_ newName: String, replacing oldName: String) -> RenameError? {
        if newName.isEmpty || newName.contains("/") || newName.contains(":") || newName == "." || newName == ".." {
            return .invalidName(newName)
        }
        if newName.utf8.count > maxNameBytes { return .tooLong }
        if newName.hasPrefix("."), !oldName.hasPrefix(".") { return .wouldHide(newName) }
        return nil
    }
}

public enum RenameError: LocalizedError, Sendable, Hashable {
    case invalidName(String)
    case alreadyExists(String)
    case duplicateInBatch(String)
    case wouldHide(String)
    case tooLong
    case vanished
    case replaced

    public var errorDescription: String? {
        switch self {
        case .invalidName(let name): return String(localized: "Invalid new name “\(name)”")
        case .alreadyExists(let name): return String(localized: "“\(name)” already exists in the same folder")
        case .duplicateInBatch(let name): return String(localized: "Another selected item would also be named “\(name)”")
        case .wouldHide(let name): return String(localized: "“\(name)” starts with a dot and would become hidden")
        case .tooLong: return String(localized: "The new name is too long")
        case .vanished: return String(localized: "No longer there: moved or deleted since the search")
        case .replaced: return String(localized: "Something else is now in its place. Search again")
        }
    }
}
