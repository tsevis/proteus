import AppKit
import Foundation

@MainActor
final class SearchModel: ObservableObject {
    @Published var folder: URL?
    @Published var term = ""
    @Published var replacement = ""
    @Published var caseSensitive = false
    @Published var useRegex = false
    @Published var includeFiles = true
    @Published var includeFolders = true
    @Published var includeHidden = false

    @Published private(set) var items: [FoundItem] = []
    @Published var selection: Set<String> = []
    @Published private(set) var status = "Διάλεξε φάκελο και γράψε τι ψάχνεις."
    @Published private(set) var failures: [String] = []
    @Published private(set) var isBusy = false

    private var lastMatcher: NameMatcher?

    var selectedItems: [FoundItem] { items.filter { selection.contains($0.id) } }
    var canSearch: Bool { folder != nil && !term.isEmpty && !isBusy }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Επιλογή"
        if panel.runModal() == .OK { folder = panel.url }
    }

    func newName(for item: FoundItem) -> String {
        lastMatcher?.replacing(in: item.name, with: replacement) ?? item.name
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
        guard let folder, !term.isEmpty else { return }
        let matcher: NameMatcher
        do {
            matcher = try NameMatcher(term: term, caseSensitive: caseSensitive, useRegex: useRegex)
        } catch {
            status = "Μη έγκυρη κανονική έκφραση: \(error.localizedDescription)"
            return
        }
        let options = ScanOptions(includeFiles: includeFiles, includeFolders: includeFolders,
                                  includeHidden: includeHidden)
        isBusy = true
        status = "Αναζήτηση…"
        defer { isBusy = false }
        do {
            let found = try await Task.detached {
                try FileScanner.scan(root: folder, matcher: matcher, options: options)
            }.value
            lastMatcher = matcher
            items = found
            selection = Set(found.map(\.id))
            status = "Βρέθηκαν \(found.count) αντικείμενα."
        } catch {
            status = "Σφάλμα αναζήτησης: \(error.localizedDescription)"
        }
    }

    func renameSelected() async {
        guard let matcher = lastMatcher else { return }
        let targets = selectedItems
        let replacement = replacement
        await perform("Μετονομάστηκαν") {
            FileActions.rename(targets, matcher: matcher, replacement: replacement)
        }
    }

    func trashSelected() async {
        let targets = selectedItems
        await perform("Μεταφέρθηκαν στον Κάδο") { FileActions.trash(targets) }
    }

    private func perform(_ verb: String, _ action: @escaping @Sendable () -> ActionReport) async {
        isBusy = true
        let report = await Task.detached(operation: action).value
        isBusy = false
        failures = report.failures
        await search()
        let failNote = report.failures.isEmpty ? "" : " — \(report.failures.count) απέτυχαν"
        status = "\(verb): \(report.succeeded)\(failNote). " + status
    }
}
