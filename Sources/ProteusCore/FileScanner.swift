import Foundation

public struct FoundItem: Identifiable, Hashable, Sendable {
    public let url: URL
    public let isDirectory: Bool
    public let depth: Int
    /// The file system's identity for the item at scan time, so an action can
    /// tell when something else has since taken its place.
    public let fileID: FileFingerprint?
    public let created: Date?
    public let modified: Date?
    public let size: Int64?
    public let tags: [String]

    public init(url: URL, isDirectory: Bool, depth: Int, fileID: FileFingerprint?,
                created: Date? = nil, modified: Date? = nil, size: Int64? = nil, tags: [String] = []) {
        self.url = url
        self.isDirectory = isDirectory
        self.depth = depth
        self.fileID = fileID
        self.created = created
        self.modified = modified
        self.size = size
        self.tags = tags
    }

    public var id: String { url.path }
    public var name: String { url.lastPathComponent }
}

/// A deleted file's inode number can be handed to a new file, so identity also needs the creation date.
public struct FileFingerprint: Hashable, Sendable, Codable {
    let inode: UInt64
    let created: Date?

    init?(_ values: URLResourceValues) {
        guard let inode = values.fileIdentifier else { return nil }
        self.inode = inode
        self.created = values.creationDate
    }
}

public struct ScanOptions: Sendable {
    public let includeFiles: Bool
    public let includeFolders: Bool
    public let includeHidden: Bool
    public let filters: ScanFilters

    public init(includeFiles: Bool, includeFolders: Bool, includeHidden: Bool, filters: ScanFilters = ScanFilters()) {
        self.includeFiles = includeFiles
        self.includeFolders = includeFolders
        self.includeHidden = includeHidden
        self.filters = filters
    }
}

public enum FileScanner {
    /// Folders whose contents belong to a tool, not to the user, even when
    /// hidden files are shown.
    static let protectedFolders: Set<String> = [".git", ".Trash", ".Trashes", ".Spotlight-V100", ".fseventsd"]

    static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .fileIdentifierKey, .creationDateKey,
        .contentModificationDateKey, .fileSizeKey, .tagNamesKey, .isHiddenKey,
    ]

    /// Walks `root` recursively and returns every item whose name matches.
    /// Packages (apps, Photos and Final Cut libraries…) are listed as single
    /// items; nothing inside them is ever offered for renaming.
    public static func scan(root: URL, matcher: NameMatcher, options: ScanOptions) throws -> [FoundItem] {
        try refuseIfInsidePackage(root)
        var enumOptions: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !options.includeHidden { enumOptions.insert(.skipsHiddenFiles) }

        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: enumOptions
        ) else {
            throw CocoaError(.fileReadNoPermission, userInfo: [NSFilePathErrorKey: root.path])
        }

        let rootDepth = root.standardizedFileURL.pathComponents.count
        var results: [FoundItem] = []
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            if protectedFolders.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            if let item = inspect(url, rootDepth: rootDepth, matcher: matcher, options: options) {
                results.append(item)
            }
        }
        return sorted(results)
    }

    /// Turns paths Spotlight reported into items, applying every rule the
    /// folder walk applies: inside `root`, not inside a package or a protected
    /// folder, hidden only when asked, and a real match.
    public static func filterIndexHits(_ paths: [String], root: URL, matcher: NameMatcher,
                                       options: ScanOptions) -> [FoundItem] {
        let realRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = realRoot.path
        let rootDepth = realRoot.pathComponents.count
        var packageCache: [String: Bool] = [:]
        let items = paths.compactMap { path -> FoundItem? in
            let url = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
            guard url.path.hasPrefix(rootPath + "/") else { return nil }
            let inside = url.pathComponents.dropFirst(rootDepth)
            if inside.contains(where: protectedFolders.contains) { return nil }
            if !options.includeHidden, inside.contains(where: { $0.hasPrefix(".") }) { return nil }
            if hasPackageAncestor(url, rootDepth: rootDepth, cache: &packageCache) { return nil }
            return inspect(url, rootDepth: rootDepth, matcher: matcher, options: options)
        }
        return sorted(items)
    }

    /// The enumerator skips packages below the root, never the root itself:
    /// a Photos library opened as the folder would be walked like any other.
    public static func refuseIfInsidePackage(_ root: URL) throws {
        var url = root.standardizedFileURL
        while url.pathComponents.count > 1 {
            if (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true {
                throw CocoaError(.fileReadNoPermission, userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "“\(url.lastPathComponent)” is a package (an app or a library). Proteus does not work inside packages."),
                ])
            }
            url = url.deletingLastPathComponent()
        }
    }

    static func hasPackageAncestor(_ url: URL, rootDepth: Int, cache: inout [String: Bool]) -> Bool {
        var parent = url.deletingLastPathComponent()
        while parent.pathComponents.count > rootDepth {
            let path = parent.path
            let isPackage = cache[path] ?? ((try? parent.resourceValues(forKeys: [.isPackageKey]))?.isPackage ?? false)
            cache[path] = isPackage
            if isPackage { return true }
            parent = parent.deletingLastPathComponent()
        }
        return false
    }

    static func inspect(_ url: URL, rootDepth: Int, matcher: NameMatcher, options: ScanOptions) -> FoundItem? {
        let values = try? url.resourceValues(forKeys: Set(keys))
        let isDir = (values?.isDirectory ?? false) && !(values?.isPackage ?? false)
        if !options.includeHidden, values?.isHidden == true { return nil }
        guard isDir ? options.includeFolders : options.includeFiles else { return nil }
        guard matcher.matches(url.lastPathComponent) else { return nil }
        let item = FoundItem(
            url: url, isDirectory: isDir,
            depth: url.standardizedFileURL.pathComponents.count - rootDepth,
            fileID: values.flatMap(FileFingerprint.init),
            created: values?.creationDate, modified: values?.contentModificationDate,
            size: values?.fileSize.map(Int64.init), tags: values?.tagNames ?? []
        )
        return options.filters.accepts(item) ? item : nil
    }

    static func sorted(_ items: [FoundItem]) -> [FoundItem] {
        items.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
    }

    /// The current identity of whatever is at `url`, or nil if nothing is.
    /// Reads from disk: URLs from the scan cache their resource values.
    public static func fileID(at url: URL) -> FileFingerprint? {
        let fresh = URL(fileURLWithPath: url.path)
        return (try? fresh.resourceValues(forKeys: [.fileIdentifierKey, .creationDateKey])).flatMap(FileFingerprint.init)
    }
}
