import Foundation

/// Ready-made rewrites of a whole name, so common jobs need no regex.
public enum NameTransform: String, CaseIterable, Sendable, Codable, Identifiable {
    case none
    case lowercase
    case uppercase
    case titleCase
    case slug
    case latin
    case stripAccents
    case spacesToDashes
    case spacesToUnderscores
    case tidySpaces

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: String(localized: "No change")
        case .lowercase: String(localized: "lowercase")
        case .uppercase: String(localized: "UPPERCASE")
        case .titleCase: String(localized: "Title Case")
        case .slug: String(localized: "Web slug (greek-to-latin-lowercase)")
        case .latin: String(localized: "Greek/Cyrillic to Latin")
        case .stripAccents: String(localized: "Remove accents")
        case .spacesToDashes: String(localized: "Spaces to dashes")
        case .spacesToUnderscores: String(localized: "Spaces to underscores")
        case .tidySpaces: String(localized: "Tidy spaces")
        }
    }

    /// Rewrites a piece of text.
    public func apply(to text: String) -> String {
        switch self {
        case .none: text
        case .lowercase: text.lowercased()
        case .uppercase: text.uppercased()
        case .titleCase: text.lowercased().localizedCapitalized
        case .slug: Self.slug(text)
        case .latin: Self.latin(text)
        case .stripAccents: text.applyingTransform(.stripDiacritics, reverse: false) ?? text
        case .spacesToDashes: Self.collapse(text, into: "-")
        case .spacesToUnderscores: Self.collapse(text, into: "_")
        case .tidySpaces: Self.collapse(text, into: " ")
        }
    }

    /// Rewrites a file name. A file keeps its extension: only a slug or a
    /// lowercase rewrite touches it, and then only its case.
    public func apply(toName name: String, isDirectory: Bool) -> String {
        guard self != .none else { return name }
        let parts = NameParts(name, isDirectory: isDirectory)
        let ext = (self == .slug || self == .lowercase) ? parts.ext.lowercased() : parts.ext
        return NameParts.join(apply(to: parts.stem), ext)
    }

    static func collapse(_ text: String, into separator: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: separator)
    }

    static func slug(_ text: String) -> String {
        let ascii = latin(text).lowercased()
        var result = ""
        var pendingDash = false
        for scalar in ascii.unicodeScalars {
            if ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) {
                if pendingDash, !result.isEmpty { result.append("-") }
                result.unicodeScalars.append(scalar)
                pendingDash = false
            } else {
                pendingDash = true
            }
        }
        return result
    }

    /// Greek by the common Greeklish conventions (θ→th, χ→ch, ου→ou, μπ→b at a
    /// word's start), everything else by the system's Latin transliteration.
    static func latin(_ text: String) -> String {
        let plain = text.applyingTransform(.stripDiacritics, reverse: false) ?? text
        let greekless = GreekTransliteration.transliterate(plain)
        let latin = greekless.applyingTransform(.toLatin, reverse: false) ?? greekless
        return latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
    }
}

/// A name split into stem and extension. Folders and hidden files have no extension.
public struct NameParts: Sendable, Hashable {
    public let stem: String
    public let ext: String

    public init(_ name: String, isDirectory: Bool) {
        let ext = isDirectory ? "" : (name as NSString).pathExtension
        // ".bashrc" or a trailing dot: no real extension to protect.
        if ext.isEmpty || name.count <= ext.count + 1 {
            stem = name
            self.ext = ""
        } else {
            stem = String(name.dropLast(ext.count + 1))
            self.ext = ext
        }
    }

    public static func join(_ stem: String, _ ext: String) -> String {
        ext.isEmpty ? stem : "\(stem).\(ext)"
    }
}

enum GreekTransliteration {
    static let pairs: [String: String] = [
        "ου": "ou", "αυ": "av", "ευ": "ev", "γγ": "ng", "γκ": "gk", "ντ": "nt",
    ]
    static let singles: [Character: String] = [
        "α": "a", "β": "v", "γ": "g", "δ": "d", "ε": "e", "ζ": "z", "η": "i", "θ": "th",
        "ι": "i", "κ": "k", "λ": "l", "μ": "m", "ν": "n", "ξ": "x", "ο": "o", "π": "p",
        "ρ": "r", "σ": "s", "ς": "s", "τ": "t", "υ": "y", "φ": "f", "χ": "ch", "ψ": "ps", "ω": "o",
    ]

    static func transliterate(_ text: String) -> String {
        let chars = Array(text)
        var result = ""
        var index = 0
        while index < chars.count {
            let current = chars[index]
            let next = index + 1 < chars.count ? chars[index + 1] : nil
            let atWordStart = index == 0 || !chars[index - 1].isLetter
            if let next, let latin = pair(current, next, atWordStart: atWordStart) {
                result += cased(latin, like: current, next: next)
                index += 2
            } else if let latin = singles[Character(current.lowercased())] {
                result += cased(latin, like: current, next: next)
                index += 1
            } else {
                result.append(current)
                index += 1
            }
        }
        return result
    }

    private static func pair(_ first: Character, _ second: Character, atWordStart: Bool) -> String? {
        let key = (String(first) + String(second)).lowercased()
        if key == "μπ" { return atWordStart ? "b" : "mp" }
        return pairs[key]
    }

    /// "Θ" in "ΘΕΑ" becomes "TH", in "Θέα" "Th".
    private static func cased(_ latin: String, like source: Character, next: Character?) -> String {
        guard source.isUppercase else { return latin }
        if let next, next.isUppercase { return latin.uppercased() }
        return latin.prefix(1).uppercased() + latin.dropFirst()
    }
}
