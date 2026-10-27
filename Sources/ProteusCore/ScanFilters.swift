import Foundation

/// Narrows a search beyond the name. An empty filter accepts everything.
public struct ScanFilters: Sendable, Hashable {
    /// Lowercased, without the dot. When set, only files are accepted.
    public let extensions: Set<String>
    /// When set, only files are accepted: a folder has no meaningful size.
    public let minBytes: Int64?
    public let maxBytes: Int64?
    public let modifiedAfter: Date?
    public let modifiedBefore: Date?
    /// A Finder tag the item must carry, compared without regard to case.
    public let tag: String?

    public init(extensions: Set<String> = [], minBytes: Int64? = nil, maxBytes: Int64? = nil,
                modifiedAfter: Date? = nil, modifiedBefore: Date? = nil, tag: String? = nil) {
        self.extensions = extensions
        self.minBytes = minBytes
        self.maxBytes = maxBytes
        self.modifiedAfter = modifiedAfter
        self.modifiedBefore = modifiedBefore
        self.tag = tag
    }

    /// Reads "jpg, .PSD  ai" as ["jpg", "psd", "ai"].
    public static func parseExtensions(_ text: String) -> Set<String> {
        let parts = text.split { $0 == "," || $0 == " " || $0 == ";" }
        return Set(parts.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased() }
            .filter { !$0.isEmpty })
    }

    public var isEmpty: Bool { self == ScanFilters() }

    public func accepts(_ item: FoundItem) -> Bool {
        if !extensions.isEmpty {
            guard !item.isDirectory, extensions.contains(item.url.pathExtension.lowercased()) else { return false }
        }
        if minBytes != nil || maxBytes != nil {
            guard !item.isDirectory, let size = item.size else { return false }
            if let minBytes, size < minBytes { return false }
            if let maxBytes, size > maxBytes { return false }
        }
        if let modifiedAfter, (item.modified ?? .distantPast) < modifiedAfter { return false }
        if let modifiedBefore, (item.modified ?? .distantFuture) > modifiedBefore { return false }
        if let tag, !tag.isEmpty {
            guard item.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) else { return false }
        }
        return true
    }
}
