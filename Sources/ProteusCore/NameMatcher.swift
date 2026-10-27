import Foundation

/// Decides whether a file name matches the search term and computes the new name.
public struct NameMatcher: Sendable {
    public let term: String
    public let caseSensitive: Bool
    public let useRegex: Bool
    private let regex: NSRegularExpression?

    public init(term: String, caseSensitive: Bool, useRegex: Bool) throws {
        self.term = term
        self.caseSensitive = caseSensitive
        self.useRegex = useRegex
        if useRegex {
            let options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
            self.regex = try NSRegularExpression(pattern: term.precomposedStringWithCanonicalMapping,
                                                 options: options)
        } else {
            self.regex = nil
        }
    }

    private var stringOptions: String.CompareOptions {
        caseSensitive ? [] : [.caseInsensitive]
    }

    /// An empty term lists everything, so a transform or a batch rename can
    /// work on a whole folder.
    public var matchesEverything: Bool { term.isEmpty }

    public func matches(_ name: String) -> Bool {
        if matchesEverything { return true }
        if let regex {
            return !nonEmptyMatches(of: regex, in: name.precomposedStringWithCanonicalMapping).isEmpty
        }
        return name.range(of: term, options: stringOptions) != nil
    }

    /// Returns the name with every occurrence of the term replaced.
    /// In regex mode the replacement may use $1, $2… for captured groups.
    /// Zero-length regex matches (`x*`, `^`, `\b`) are ignored, so a pattern
    /// can never select or rewrite a name it does not visibly contain.
    public func replacing(in name: String, with replacement: String) -> String {
        if matchesEverything { return name }
        guard let regex else {
            return name.replacingOccurrences(of: term, with: replacement, options: stringOptions)
        }
        let source = name.precomposedStringWithCanonicalMapping
        let matches = nonEmptyMatches(of: regex, in: source)
        guard !matches.isEmpty else { return name }
        let result = NSMutableString(string: source)
        var offset = 0
        for match in matches {
            let substitute = regex.replacementString(for: match, in: source, offset: 0, template: replacement)
            let range = NSRange(location: match.range.location + offset, length: match.range.length)
            result.replaceCharacters(in: range, with: substitute)
            offset += (substitute as NSString).length - match.range.length
        }
        return result as String
    }

    /// Where the term occurs in `name`, for highlighting. Regex ranges refer
    /// to the NFC form of the name, which is also what the table shows.
    public func ranges(in name: String) -> [Range<String.Index>] {
        if matchesEverything { return [] }
        guard let regex else {
            var found: [Range<String.Index>] = []
            var start = name.startIndex
            while let range = name.range(of: term, options: stringOptions, range: start..<name.endIndex) {
                found.append(range)
                start = range.upperBound
            }
            return found
        }
        let source = name.precomposedStringWithCanonicalMapping
        return nonEmptyMatches(of: regex, in: source).compactMap { Range($0.range, in: source) }
    }

    private func nonEmptyMatches(of regex: NSRegularExpression, in name: String) -> [NSTextCheckingResult] {
        regex.matches(in: name, range: NSRange(name.startIndex..., in: name))
            .filter { $0.range.length > 0 }
    }
}

extension NameMatcher {
    /// The Find & Replace tab's new name: replace, then transform. With
    /// `keepExtension` a file's extension is left exactly as it is.
    public func proposedName(for item: FoundItem, replacement: String, keepExtension: Bool,
                             transform: NameTransform) -> String {
        guard keepExtension else {
            return transform.apply(toName: replacing(in: item.name, with: replacement), isDirectory: item.isDirectory)
        }
        let parts = NameParts(item.name, isDirectory: item.isDirectory)
        let stem = transform.apply(to: replacing(in: parts.stem, with: replacement))
        return NameParts.join(stem, parts.ext)
    }
}
