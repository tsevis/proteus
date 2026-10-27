import Foundation

/// Decides whether a file name matches the search term and computes the new name.
struct NameMatcher: Sendable {
    let term: String
    let caseSensitive: Bool
    let useRegex: Bool
    private let regex: NSRegularExpression?

    init(term: String, caseSensitive: Bool, useRegex: Bool) throws {
        self.term = term
        self.caseSensitive = caseSensitive
        self.useRegex = useRegex
        if useRegex {
            let options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
            self.regex = try NSRegularExpression(pattern: term, options: options)
        } else {
            self.regex = nil
        }
    }

    private var stringOptions: String.CompareOptions {
        caseSensitive ? [] : [.caseInsensitive]
    }

    func matches(_ name: String) -> Bool {
        if let regex {
            let range = NSRange(name.startIndex..., in: name)
            return regex.firstMatch(in: name, range: range) != nil
        }
        return name.range(of: term, options: stringOptions) != nil
    }

    /// Returns the name with every occurrence of the term replaced.
    /// In regex mode the replacement may use $1, $2… for captured groups.
    func replacing(in name: String, with replacement: String) -> String {
        if let regex {
            let range = NSRange(name.startIndex..., in: name)
            return regex.stringByReplacingMatches(in: name, range: range, withTemplate: replacement)
        }
        return name.replacingOccurrences(of: term, with: replacement, options: stringOptions)
    }
}
