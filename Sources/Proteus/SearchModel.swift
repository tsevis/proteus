import AppKit
import Foundation
import ProteusCore

@MainActor
final class SearchModel: ObservableObject {
    // Changing any search input discards the results, so an action can only
    // ever use the search the table and the confirmation dialog describe.
    @Published var folder: URL? { didSet { if folder != oldValue { discardResults() } } }
    @Published var term = "" { didSet { if term != oldValue { discardResults() } } }
    @Published var caseSensitive = false { didSet { if caseSensitive != oldValue { discardResults() } } }
    @Published var useRegex = false { didSet { if useRegex != oldValue { discardResults() } } }
    @Published var includeFiles = true { didSet { if includeFiles != oldValue { discardResults() } } }
    @Published var includeFolders = true { didSet { if includeFolders != oldValue { discardResults() } } }
    @Published var includeHidden = false { didSet { if includeHidden != oldValue { discardResults() } } }
    @Published var replacement = ""

    @Published private(set) var items: [FoundItem] = []
    @Published var selection: Set<String> = []
    @Published private(set) var status = String(localized: "Choose a folder and type what you are looking for.")
    @Published private(set) var failures: [String] = []
    @Published private(set) var isBusy = false

    /// The matcher of the search whose results are on screen.
    private(set) var searched: NameMatcher?
    /// Bumped by every search and every discard, so a slow scan that finishes
    /// after the inputs changed cannot put stale results on screen.
    private var generation = 0

    var selectedItems: [FoundItem] { items.filter { selection.contains($0.id) } }
    var canSearch: Bool { folder != nil && !term.isEmpty && !isBusy }
    var canAct: Bool { searched != nil && !selection.isEmpty && !isBusy }

    /// Selected items whose name the rename would actually change.
    var renameTargets: [FoundItem] {
        guard let searched else { return [] }
        return selectedItems.filter {
            FileActions.plannedName(for: $0, matcher: searched, replacement: replacement) != nil
        }
    }

    /// Selected items not already inside another selected folder.
    var trashTargets: [FoundItem] {
        let selected = selectedItems
        let covered = FileActions.coveredByFolder(selected)
        return selected.filter { !covered.contains($0.id) }
    }

    /// A few "old → new" lines for the confirmation dialog.
    var renameExamples: String {
        renameTargets.prefix(3).map { "\($0.name) → \(newName(for: $0))" }.joined(separator: "\n")
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose")
        if panel.runModal() == .OK { folder = panel.url }
    }

    func newName(for item: FoundItem) -> String {
        searched?.replacing(in: item.name, with: replacement) ?? item.name
    }

    func relativeLocation(of item: FoundItem) -> String {
        guard let root = folder?.standardizedFileURL.path else { return item.url.path }
        let parent = item.url.deletingLastPathComponent().standardizedFileURL.path
        let rel = parent.hasPrefix(root) ? String(parent.dropFirst(root.count)) : parent
        return rel.isEmpty ? "/" : rel
    }

    func selectAll() { selection = Set(items.map(\.id)) }
    func selectNone() { selection = [] }

    func search() async {
        guard canSearch, let folder else { return }
        let matcher: NameMatcher
        do {
            matcher = try NameMatcher(term: term, caseSensitive: caseSensitive, useRegex: useRegex)
        } catch {
            status = String(localized: "Invalid regular expression: \(error.localizedDescription)")
            return
        }
        let options = ScanOptions(includeFiles: includeFiles, includeFolders: includeFolders,
                                  includeHidden: includeHidden)
        generation += 1
        let mine = generation
        isBusy = true
        status = String(localized: "Searching…")
        defer { isBusy = false }
        do {
            let found = try await Task.detached {
                try FileScanner.scan(root: folder, matcher: matcher, options: options)
            }.value
            guard mine == generation else { return }
            searched = matcher
            items = found
            selection = Set(found.map(\.id))
            status = String(localized: "Found: \(found.count)")
        } catch {
            guard mine == generation else { return }
            status = String(localized: "Search error: \(error.localizedDescription)")
        }
    }

    func renameSelected() async {
        guard canAct, let matcher = searched else { return }
        let targets = renameTargets
        let replacement = replacement
        await perform({ String(localized: "Renamed: \($0)") }) {
            FileActions.rename(targets, matcher: matcher, replacement: replacement)
        }
    }

    func trashSelected() async {
        guard canAct else { return }
        let targets = selectedItems
        await perform({ String(localized: "Moved to Trash: \($0)") }) { FileActions.trash(targets) }
    }

    private func discardResults() {
        generation += 1
        guard searched != nil || !items.isEmpty else { return }
        searched = nil
        items = []
        selection = []
        status = String(localized: "Settings changed. Press Search again.")
    }

    private func perform(_ summary: (Int) -> String, _ action: @escaping @Sendable () -> ActionReport) async {
        isBusy = true
        let report = await Task.detached(operation: action).value
        isBusy = false
        failures = report.failures
        await search()
        let failNote = report.failures.isEmpty ? "" : " — " + String(localized: "Failed: \(report.failures.count)")
        status = summary(report.succeeded) + failNote + ". " + status
    }
}
