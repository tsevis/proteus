import ProteusCore
import QuickLook
import SwiftUI

/// The search results, each with the name it will get and anything that
/// stands in the way, before a single file is touched.
struct ResultsTable: View {
    @ObservedObject var model: SearchModel

    var body: some View {
        Table(model.items, selection: $model.highlighted) {
            TableColumn("") { item in
                Toggle("", isOn: checkBinding(for: item)).labelsHidden()
            }
            .width(24)
            TableColumn("Name") { item in
                Label {
                    Text(highlighted(item.name))
                } icon: {
                    Image(systemName: item.isDirectory ? "folder" : "doc")
                }
                .help(item.name)
            }
            TableColumn("New name") { item in newNameCell(item) }
            TableColumn("Location") { item in
                Text(verbatim: model.relativeLocation(of: item)).foregroundStyle(.secondary)
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            Button("Quick Look") { highlight(ids); model.quickLookHighlighted() }
            Button("Reveal in Finder") { highlight(ids); model.revealHighlighted() }
            Button("Open") { highlight(ids); model.openHighlighted() }
            Divider()
            Button("Check") { model.selection.formUnion(ids) }
            Button("Uncheck") { model.selection.subtract(ids) }
            Divider()
            Button("Remove from List") { model.removeFromList(ids) }
        } primaryAction: { ids in
            highlight(ids)
            model.openHighlighted()
        }
        // Delete takes the highlighted rows out of the list; nothing on disk changes.
        .onDeleteCommand { model.removeFromList(model.highlighted) }
        .onKeyPress(.space) {
            guard !model.highlighted.isEmpty else { return .ignored }
            model.previewURL = model.previewURL == nil ? model.highlightedURLs.first : nil
            return .handled
        }
        .quickLookPreview($model.previewURL, in: model.highlightedURLs)
        // Dropped onto the list, files and folders are added as they are,
        // to rename; a folder is not searched inside.
        .dropDestination(for: URL.self) { urls, _ in
            model.addItems(urls)
            return !urls.isEmpty
        }
        .overlay {
            if model.items.isEmpty { emptyHint }
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down").font(.largeTitle).foregroundStyle(.tertiary)
            Text("Two ways to fill this list")
                .font(.headline)
            Text("Choose a Folder… and press Search: an empty name field lists everything inside it.")
            Text("Or drag files and folders from Finder onto this list, or use Add Files…")
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
        .padding(24)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func newNameCell(_ item: FoundItem) -> some View {
        if let step = model.step(for: item) {
            if let problem = step.problem {
                Label {
                    Text(verbatim: step.newName.isEmpty ? problem.localizedDescription : step.newName)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(.red)
                .help(problem.localizedDescription)
            } else if step.isChange {
                Text(verbatim: step.newName)
                    .foregroundStyle(step.numbered ? .orange : .primary)
                    .help(step.numbered ? String(localized: "A number was added so two items would not share a name.") : step.newName)
            } else {
                Text("unchanged").foregroundStyle(.tertiary)
            }
        } else {
            Text(verbatim: "—").foregroundStyle(.tertiary)
        }
    }

    /// The part of the name the search found, marked.
    private func highlighted(_ name: String) -> AttributedString {
        guard let matcher = model.searched else { return AttributedString(name) }
        let shown = matcher.useRegex ? name.precomposedStringWithCanonicalMapping : name
        var text = AttributedString(shown)
        for range in matcher.ranges(in: shown) {
            guard let marked = Range(range, in: text) else { continue }
            text[marked].backgroundColor = .accentColor.opacity(0.28)
            text[marked].font = .body.bold()
        }
        return text
    }

    private func highlight(_ ids: Set<String>) {
        if !ids.isEmpty { model.highlighted = ids }
    }

    private func checkBinding(for item: FoundItem) -> Binding<Bool> {
        Binding(
            get: { model.selection.contains(item.id) },
            set: { isOn in
                if isOn { model.selection.insert(item.id) } else { model.selection.remove(item.id) }
            }
        )
    }
}
