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

    public func matches(_ name: String) -> Bool {
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

    private func nonEmptyMatches(of regex: NSRegularExpression, in name: String) -> [NSTextCheckingResult] {
        regex.matches(in: name, range: NSRange(name.startIndex..., in: name))
            .filter { $0.range.length > 0 }
    }
}
