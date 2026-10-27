import AppKit
import Foundation
import ProteusCore

/// Files and folders added by hand, for renaming without a search.
extension SearchModel {
    var hasPicked: Bool { !pickedPaths.isEmpty }

    func chooseItems() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.treatsFilePackagesAsDirectories = false
        panel.prompt = String(localized: "Add")
        if panel.runModal() == .OK { addItems(panel.urls) }
    }

    func addItems(_ urls: [URL]) {
        guard !isBusy, !urls.isEmpty else { return }
        let result = FileScanner.items(for: urls)
        let known = Set(pickedPaths)
        let fresh = result.items.map(\.id).filter { !known.contains($0) }
        pickedPaths += fresh
        mergePicked()
        replan()
        status = String(localized: "Added: \(fresh.count)")
        if !result.refused.isEmpty {
            failures = result.refused.map { String(localized: "\($0): inside a package or a protected folder, not added") }
        }
    }

    /// Puts the hand-picked items into the list, checked, beside any search
    /// results. Items that have gone from the disk are dropped.
    func mergePicked() {
        guard hasPicked else { return }
        let current = FileScanner.items(for: pickedPaths.map { URL(fileURLWithPath: $0) }).items
        pickedPaths = current.map(\.id)
        let known = Set(items.map(\.id))
        let fresh = current.filter { !known.contains($0.id) }
        items += fresh
        selection.formUnion(fresh.map(\.id))
        if searched == nil {
            searched = try? NameMatcher(term: "", caseSensitive: false, useRegex: false)
        }
    }

    func clearList() {
        pickedPaths = []
        searched = nil
        items = []
        selection = []
        status = String(localized: "Choose a folder and type what you are looking for.")
    }

    /// After an action: search the folder again, or just reload the hand-picked list.
    func refresh() async {
        if folder != nil {
            await search()
            return
        }
        searched = nil
        items = []
        selection = []
        mergePicked()
        replan()
        status = ""
    }
}
