import Foundation

/// One row of a batch rename, in the manner of Adobe Bridge: each row names
/// what goes in this part of the new name and carries only the controls that
/// kind needs. Rows are applied top to bottom.
public struct BatchRule: Identifiable, Hashable, Codable, Sendable {
    public enum Kind: String, CaseIterable, Codable, Sendable {
        case text, currentName, sequenceNumber, sequenceLetter, date, folderName, replace, transform, newExtension

        public var title: String {
            switch self {
            case .text: String(localized: "Text")
            case .currentName: String(localized: "Current name")
            case .sequenceNumber: String(localized: "Sequence number")
            case .sequenceLetter: String(localized: "Sequence letter")
            case .date: String(localized: "Date")
            case .folderName: String(localized: "Folder name")
            case .replace: String(localized: "Find and replace")
            case .transform: String(localized: "Transform")
            case .newExtension: String(localized: "New extension")
            }
        }
    }

    public enum DateSource: String, CaseIterable, Codable, Sendable {
        case created, modified, taken

        public var title: String {
            switch self {
            case .created: String(localized: "Created")
            case .modified: String(localized: "Modified")
            case .taken: String(localized: "Photo taken")
            }
        }
    }

    public var id = UUID()
    public var kind: Kind
    /// The literal text, the first number, the date format, the text to find, the extension.
    public var text: String
    /// The replacement for a find-and-replace row.
    public var replacement: String
    public var digits: Int
    public var transform: NameTransform
    public var dateSource: DateSource

    public init(kind: Kind, text: String = "", replacement: String = "", digits: Int = 3,
                transform: NameTransform = .lowercase, dateSource: DateSource = .created) {
        self.kind = kind
        self.text = text
        self.replacement = replacement
        self.digits = digits
        self.transform = transform
        self.dateSource = dateSource
    }

    public static func starter(_ kind: Kind) -> BatchRule {
        switch kind {
        case .sequenceNumber: BatchRule(kind: kind, text: "1")
        case .date: BatchRule(kind: kind, text: "yyyy-MM-dd")
        default: BatchRule(kind: kind)
        }
    }
}

public enum BatchRenamer {
    /// The new name for one item.
    /// - Parameters:
    ///   - position: its place in the batch, from zero.
    ///   - taken: when the photo was taken, if a date row needs it.
    public static func name(for item: FoundItem, rules: [BatchRule], position: Int, taken: Date? = nil) -> String {
        let parts = NameParts(item.name, isDirectory: item.isDirectory)
        var built = ""
        var ext = parts.ext
        for rule in rules {
            switch rule.kind {
            case .text:
                built += rule.text
            case .currentName:
                built += parts.stem
            case .sequenceNumber:
                let start = Int(rule.text.trimmingCharacters(in: .whitespaces)) ?? 1
                built += String(format: "%0\(max(1, min(rule.digits, 9)))d", start + position)
            case .sequenceLetter:
                built += letters(for: position)
            case .date:
                built += formatted(date(for: item, source: rule.dateSource, taken: taken), format: rule.text)
            case .folderName:
                built += item.url.deletingLastPathComponent().lastPathComponent
            case .replace:
                // A pass over the name built so far, as in Bridge.
                if let matcher = try? NameMatcher(term: rule.text, caseSensitive: false, useRegex: false) {
                    built = matcher.replacing(in: built, with: rule.replacement)
                }
            case .transform:
                built = rule.transform.apply(to: built)
            case .newExtension:
                if !item.isDirectory { ext = rule.text.trimmingCharacters(in: CharacterSet(charactersIn: ". ")) }
            }
        }
        // A slash would move the item into another folder; a colon shows as a
        // slash in Finder. Neither is ever what the preview meant.
        let safe = built.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return NameParts.join(safe, ext)
    }

    /// Positions for `items` in order, counting from zero, optionally starting
    /// again in every folder.
    public static func positions(for items: [FoundItem], restartPerFolder: Bool) -> [Int] {
        var counters: [String: Int] = [:]
        return items.map { item in
            let key = restartPerFolder ? item.url.deletingLastPathComponent().path : ""
            let position = counters[key, default: 0]
            counters[key] = position + 1
            return position
        }
    }

    /// `a`, `b`, … `z`, `aa`, `ab`…
    public static func letters(for position: Int) -> String {
        var value = max(0, position)
        var result = ""
        repeat {
            result = String(UnicodeScalar(UInt8(97 + value % 26))) + result
            value = value / 26 - 1
        } while value >= 0
        return result
    }

    static func date(for item: FoundItem, source: BatchRule.DateSource, taken: Date?) -> Date? {
        switch source {
        case .created: item.created
        case .modified: item.modified
        case .taken: taken ?? item.created
        }
    }

    static func formatted(_ date: Date?, format: String) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format.isEmpty ? "yyyy-MM-dd" : format
        return formatter.string(from: date)
    }
}
