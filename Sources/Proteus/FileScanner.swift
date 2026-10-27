import Foundation

struct FoundItem: Identifiable, Hashable, Sendable {
    let url: URL
    let isDirectory: Bool
    let depth: Int

    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

struct ScanOptions: Sendable {
    let includeFiles: Bool
    let includeFolders: Bool
    let includeHidden: Bool
}

enum FileScanner {
    /// Walks `root` recursively and returns every item whose name matches.
    static func scan(root: URL, matcher: NameMatcher, options: ScanOptions) throws -> [FoundItem] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        var enumOptions: FileManager.DirectoryEnumerationOptions = []
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
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isDir = (values?.isDirectory ?? false) && !(values?.isPackage ?? false)
            guard isDir ? options.includeFolders : options.includeFiles else { continue }
            guard matcher.matches(url.lastPathComponent) else { continue }
            let depth = url.standardizedFileURL.pathComponents.count - rootDepth
            results.append(FoundItem(url: url, isDirectory: isDir, depth: depth))
        }
        return results.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
    }
}
