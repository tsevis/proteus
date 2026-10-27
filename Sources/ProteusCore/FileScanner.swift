import Foundation

public struct FoundItem: Identifiable, Hashable, Sendable {
    public let url: URL
    public let isDirectory: Bool
    public let depth: Int
    /// The file system's identity for the item at scan time, so an action can
    /// tell when something else has since taken its place.
    public let fileID: FileFingerprint?

    public var id: String { url.path }
    public var name: String { url.lastPathComponent }
}

/// A deleted file's inode number can be handed to a new file, so identity also needs the creation date.
public struct FileFingerprint: Hashable, Sendable {
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

    public init(includeFiles: Bool, includeFolders: Bool, includeHidden: Bool) {
        self.includeFiles = includeFiles
        self.includeFolders = includeFolders
        self.includeHidden = includeHidden
    }
}

public enum FileScanner {
    /// Folders whose contents belong to a tool, not to the user, even when
    /// hidden files are shown.
    static let protectedFolders: Set<String> = [".git", ".Trash", ".Trashes", ".Spotlight-V100", ".fseventsd"]

    static let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .fileIdentifierKey, .creationDateKey]

    /// Walks `root` recursively and returns every item whose name matches.
    /// Packages (apps, Photos and Final Cut libraries…) are listed as single
    /// items; nothing inside them is ever offered for renaming.
    public static func scan(root: URL, matcher: NameMatcher, options: ScanOptions) throws -> [FoundItem] {
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
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isDir = (values?.isDirectory ?? false) && !(values?.isPackage ?? false)
            guard isDir ? options.includeFolders : options.includeFiles else { continue }
            guard matcher.matches(url.lastPathComponent) else { continue }
            let depth = url.standardizedFileURL.pathComponents.count - rootDepth
            results.append(FoundItem(url: url, isDirectory: isDir, depth: depth, fileID: values.flatMap(FileFingerprint.init)))
        }
        return results.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
    }

    /// The current identity of whatever is at `url`, or nil if nothing is.
    /// Reads from disk: URLs from the scan cache their resource values.
    static func fileID(at url: URL) -> FileFingerprint? {
        let fresh = URL(fileURLWithPath: url.path)
        return (try? fresh.resourceValues(forKeys: [.fileIdentifierKey, .creationDateKey])).flatMap(FileFingerprint.init)
    }
}
