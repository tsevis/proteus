import AppKit
import Foundation
import ProteusCore
import UniformTypeIdentifiers

/// Trash, undo, tags and export.
extension SearchModel {
    var canUndo: Bool { lastJournal.map { !$0.entries.isEmpty } ?? false && !isBusy }

    func trashSelected() async {
        guard canTrash else { return }
        let targets = selectedItems
        await perform({ String(localized: "Moved to Trash: \($0)") }) { FileActions.trash(targets) }
    }

    func undoLast() async {
        guard canUndo, let journal = lastJournal else { return }
        isBusy = true
        let report = await Task.detached { journal.undo() }.value
        isBusy = false
        var notes: [String] = []
        lastJournal = nil
        JournalStore.clear(onError: { notes.append($0) })
        await finish(String(localized: "Restored: \(report.succeeded)"), report, notes: notes)
    }

    func tagSelected(_ tag: String, add: Bool) async {
        let tag = tag.trimmingCharacters(in: .whitespaces)
        guard canAct, !tag.isEmpty else { return }
        let targets = selectedItems
        isBusy = true
        let report = await Task.detached { add ? FileTags.add(tag, to: targets) : FileTags.remove(tag, from: targets) }.value
        isBusy = false
        let summary = add ? String(localized: "Tagged: \(report.succeeded)") : String(localized: "Untagged: \(report.succeeded)")
        await finish(summary, report)
    }

    func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "Proteus.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let header = [String(localized: "Path"), String(localized: "Name"),
                      String(localized: "New name"), String(localized: "Status")]
        let rows = items.map { item -> [String] in
            let step = step(for: item)
            let state = step?.problem?.localizedDescription
                ?? (step?.isChange == true ? String(localized: "Will be renamed") : String(localized: "Unchanged"))
            return [item.url.path, item.name, step?.newName ?? item.name, state]
        }
        do {
            try CSVExport.document([header] + rows).write(to: url, atomically: true, encoding: .utf8)
            status = String(localized: "Exported: \(url.lastPathComponent)")
        } catch {
            status = String(localized: "Export failed: \(error.localizedDescription)")
        }
    }

    func revealHighlighted() {
        NSWorkspace.shared.activateFileViewerSelecting(highlightedURLs)
    }

    func openHighlighted() {
        highlightedURLs.forEach { NSWorkspace.shared.open($0) }
    }

    func quickLookHighlighted() {
        previewURL = highlightedURLs.first
    }

    var highlightedURLs: [URL] { items.filter { highlighted.contains($0.id) }.map(\.url) }

    func perform(_ summary: (Int) -> String, _ action: @escaping @Sendable () -> ActionOutcome) async {
        isBusy = true
        let outcome = await Task.detached(operation: action).value
        isBusy = false
        var notes: [String] = []
        // Anything that changed the disk replaces the older record, so Undo
        // never reaches past this action to an earlier one.
        if outcome.report.succeeded > 0 {
            lastJournal = outcome.journal.entries.isEmpty ? nil : outcome.journal
            if let journal = lastJournal {
                JournalStore.save(journal, onError: { notes.append($0) })
            } else {
                JournalStore.clear(onError: { notes.append($0) })
            }
        }
        await finish(summary(outcome.report.succeeded), outcome.report, notes: notes)
    }

    private func finish(_ summary: String, _ report: ActionReport, notes: [String] = []) async {
        failures = notes + report.failures
        await search()
        let failNote = report.failures.isEmpty ? "" : " — " + String(localized: "Failed: \(report.failures.count)")
        status = summary + failNote + ". " + status
    }
}

/// The last action's journal, kept on disk so it can be undone after a relaunch.
enum JournalStore {
    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Proteus/last-action.json")
    }

    static func load(onError: (String) -> Void) -> Journal? {
        do { return try Journal.load(from: url) } catch {
            onError(String(localized: "Could not read the undo record: \(error.localizedDescription)"))
            return nil
        }
    }

    static func save(_ journal: Journal, onError: (String) -> Void) {
        do { try journal.save(to: url) } catch {
            onError(String(localized: "Could not save the undo record: \(error.localizedDescription)"))
        }
    }

    static func clear(onError: (String) -> Void) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do { try FileManager.default.removeItem(at: url) } catch {
            onError(String(localized: "Could not clear the undo record: \(error.localizedDescription)"))
        }
    }
}
