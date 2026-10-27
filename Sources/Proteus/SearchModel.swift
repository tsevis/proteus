import AppKit
import Foundation
import ProteusCore

@MainActor
final class SearchModel: ObservableObject {
    enum Mode: String, CaseIterable { case findReplace, batch }

    // Changing any search input discards the results, so an action can only
    // ever use the search the table and the confirmation dialog describe.
    @Published var folder: URL? { didSet { if folder != oldValue { discardResults() } } }
    @Published var term = "" { didSet { if term != oldValue { discardResults() } } }
    @Published var caseSensitive = false { didSet { if caseSensitive != oldValue { discardResults() } } }
    @Published var useRegex = false { didSet { if useRegex != oldValue { discardResults() } } }
    @Published var includeFiles = true { didSet { if includeFiles != oldValue { discardResults() } } }
    @Published var includeFolders = true { didSet { if includeFolders != oldValue { discardResults() } } }
    @Published var includeHidden = false { didSet { if includeHidden != oldValue { discardResults() } } }
    @Published var useSpotlight = false { didSet { if useSpotlight != oldValue { discardResults() } } }
    @Published var filters = FilterInputs() { didSet { if filters != oldValue { discardResults() } } }

    // Inputs of the two tabs. They only change the plan, never the results.
    @Published var mode = Mode.findReplace { didSet { rulesChanged() } }
    @Published var replacement = "" { didSet { replan() } }
    @Published var transform = NameTransform.none { didSet { replan() } }
    @Published var keepExtension = true { didSet { replan() } }
    @Published var rules: [BatchRule] = [.starter(.currentName)] { didSet { rulesChanged() } }
    @Published var numberClashes = true { didSet { replan() } }
    @Published var restartNumbering = false { didSet { replan() } }

    @Published private(set) var items: [FoundItem] = []
    @Published var selection: Set<String> = [] { didSet { if selection != oldValue { replan() } } }
    @Published var highlighted: Set<String> = []
    @Published var previewURL: URL?
    @Published var status = String(localized: "Choose a folder and type what you are looking for.")
    @Published var failures: [String] = []
    @Published var isBusy = false
    @Published private(set) var plan: [RenameStep] = []
    @Published var lastJournal: Journal?
    @Published private(set) var recentFolders: [URL] = RecentFolders.load()

    /// The matcher of the search whose results are on screen.
    private(set) var searched: NameMatcher?
    private(set) var planByID: [String: RenameStep] = [:]
    var takenDates: [String: Date] = [:]
    /// Items whose EXIF date was already looked for, found or not.
    var datesTried: Set<String> = []
    /// Bumped by every search and every discard, so a slow scan that finishes
    /// after the inputs changed cannot put stale results on screen.
    private(set) var generation = 0

    init() {
        lastJournal = JournalStore.load(onError: { [weak self] in self?.status = $0 })
    }

    var selectedItems: [FoundItem] { items.filter { selection.contains($0.id) } }
    var canSearch: Bool { folder != nil && !isBusy }
    var canAct: Bool { searched != nil && !selection.isEmpty && !isBusy }
    /// An empty search lists everything, which is fine to rename but far too
    /// broad to throw away in one click.
    var canTrash: Bool { canAct && !(searched?.matchesEverything ?? true) }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose")
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    /// Opens a folder from the panel, a drop, the Dock, Finder or the recent list.
    func open(_ url: URL) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            status = String(localized: "Not a folder: \(url.lastPathComponent)")
            return
        }
        do { try FileScanner.refuseIfInsidePackage(url) } catch {
            status = error.localizedDescription
            return
        }
        folder = url
        recentFolders = RecentFolders.remember(url)
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
                                  includeHidden: includeHidden, filters: filters.scanFilters)
        generation += 1
        let mine = generation
        isBusy = true
        status = String(localized: "Searching…")
        defer { isBusy = false }
        do {
            let found = useSpotlight
                ? try await SpotlightSearch.run(root: folder, matcher: matcher, options: options)
                : try await Task.detached { try FileScanner.scan(root: folder, matcher: matcher, options: options) }.value
            guard mine == generation else { return }
            searched = matcher
            items = found
            takenDates = [:]
            datesTried = []
            selection = Set(found.map(\.id))
            replan()
            highlighted = []
            status = String(localized: "Found: \(found.count)")
            if found.isEmpty, useSpotlight {
                status += " " + String(localized: "(Spotlight may not have indexed this folder.)")
            }
            isBusy = false
            loadTakenDatesIfNeeded()
        } catch {
            guard mine == generation else { return }
            status = String(localized: "Search error: \(error.localizedDescription)")
        }
    }

    private func discardResults() {
        generation += 1
        guard searched != nil || !items.isEmpty else { return }
        searched = nil
        items = []
        selection = []
        status = String(localized: "Settings changed. Press Search again.")
    }

    func setPlan(_ steps: [RenameStep]) {
        plan = steps
        planByID = Dictionary(uniqueKeysWithValues: steps.map { ($0.id, $0) })
    }
}
