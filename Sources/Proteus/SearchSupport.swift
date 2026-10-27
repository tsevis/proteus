import AppKit
import Foundation
import ProteusCore

/// The filter fields as typed, turned into `ScanFilters` when searching.
struct FilterInputs: Equatable {
    var extensions = ""
    var minMB = ""
    var maxMB = ""
    var useModifiedAfter = false
    var modifiedAfter = Date()
    var useModifiedBefore = false
    var modifiedBefore = Date()
    var tag = ""

    var scanFilters: ScanFilters {
        ScanFilters(
            extensions: ScanFilters.parseExtensions(extensions),
            minBytes: Self.bytes(minMB), maxBytes: Self.bytes(maxMB),
            modifiedAfter: useModifiedAfter ? Calendar.current.startOfDay(for: modifiedAfter) : nil,
            modifiedBefore: useModifiedBefore ? Self.endOfDay(modifiedBefore) : nil,
            tag: tag.trimmingCharacters(in: .whitespaces).isEmpty ? nil : tag.trimmingCharacters(in: .whitespaces)
        )
    }

    var activeCount: Int {
        [!extensions.isEmpty, !minMB.isEmpty || !maxMB.isEmpty, useModifiedAfter || useModifiedBefore, !tag.isEmpty]
            .count { $0 }
    }

    static func bytes(_ megabytes: String) -> Int64? {
        let text = megabytes.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let value = Double(text), value >= 0 else { return nil }
        return Int64(value * 1_000_000)
    }

    static func endOfDay(_ date: Date) -> Date {
        let start = Calendar.current.startOfDay(for: date)
        return Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }
}

/// The last ten folders opened, newest first.
enum RecentFolders {
    static let key = "recentFolders"
    static let limit = 10

    static func load() -> [URL] {
        (UserDefaults.standard.stringArray(forKey: key) ?? [])
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    static func remember(_ url: URL) -> [URL] {
        let paths = [url.path] + load().map(\.path).filter { $0 != url.path }
        let kept = Array(paths.prefix(limit))
        UserDefaults.standard.set(kept, forKey: key)
        return kept.map { URL(fileURLWithPath: $0) }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// Searches by name through the Spotlight index: much faster on a big tree,
/// but only as complete as the index. Every hit is checked again on disk.
@MainActor
enum SpotlightSearch {
    static func run(root: URL, matcher: NameMatcher, options: ScanOptions) async throws -> [FoundItem] {
        let query = NSMetadataQuery()
        query.searchScopes = [root]
        // The index narrows by a plain substring; the matcher then decides.
        query.predicate = matcher.useRegex || matcher.matchesEverything
            ? NSPredicate(format: "%K LIKE %@", NSMetadataItemFSNameKey, "*")
            : NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemFSNameKey, matcher.term)
        let finished = NotificationCenter.default.notifications(named: .NSMetadataQueryDidFinishGathering)
        guard query.start() else {
            throw CocoaError(.featureUnsupported, userInfo: [NSLocalizedDescriptionKey: String(localized: "Spotlight is not available.")])
        }
        let mine = ObjectIdentifier(query)
        for await note in finished where note.object.map({ ObjectIdentifier($0 as AnyObject) }) == mine { break }
        query.stop()
        let paths = (0..<query.resultCount).compactMap {
            (query.result(at: $0) as? NSMetadataItem)?.value(forAttribute: NSMetadataItemPathKey) as? String
        }
        return await Task.detached {
            FileScanner.filterIndexHits(paths, root: root, matcher: matcher, options: options)
        }.value
    }
}

/// Folders handed to Proteus from outside: the Dock icon, Finder's Services menu.
@MainActor
final class FolderInbox: ObservableObject {
    static let shared = FolderInbox()
    @Published var pending: URL?
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        Task { @MainActor in FolderInbox.shared.pending = url }
    }

    /// Finder ▸ Services ▸ Rename with Proteus.
    @objc func openInProteus(_ pasteboard: NSPasteboard, userData: String?,
                             error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let url = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL])?.first else {
            error.pointee = String(localized: "No folder was passed to Proteus.") as NSString
            return
        }
        NSApp.activate()
        Task { @MainActor in FolderInbox.shared.pending = url }
    }
}
