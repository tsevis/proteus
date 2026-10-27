import ProteusCore
import SwiftUI

/// Where to look and what for: folder, name, kinds of item and filters.
struct ScopeForm: View {
    @ObservedObject var model: SearchModel
    @State private var showFilters = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Folder…") { model.chooseFolder() }
                    .help("Search inside a folder and its subfolders")
                recentMenu
                Button("Add Files…") { model.chooseItems() }
                    .help("Add files or folders to the list directly, without a search. You can also drag them onto the list.")
                Group {
                    if let path = model.folder?.path { Text(verbatim: path) } else { Text("No folder — or drop one here") }
                }
                .foregroundStyle(model.folder == nil ? .secondary : .primary)
                .lineLimit(1).truncationMode(.middle)
            }
            HStack {
                TextField("Name contains… (empty lists everything)", text: $model.term)
                    .onSubmit { Task { await model.search() } }
                Button("Search") { Task { await model.search() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canSearch)
            }
            HStack(spacing: 16) {
                Toggle("Files", isOn: $model.includeFiles)
                Toggle("Folders", isOn: $model.includeFolders)
                Toggle("Hidden", isOn: $model.includeHidden)
                Toggle("Match case", isOn: $model.caseSensitive)
                Toggle("Regex", isOn: $model.useRegex)
                Toggle("Spotlight (fast)", isOn: $model.useSpotlight)
                    .help("Searches the Spotlight index: much faster on big folders, but only finds what Spotlight has indexed.")
                Spacer()
                Button {
                    showFilters.toggle()
                } label: {
                    Label(filterTitle, systemImage: "line.3.horizontal.decrease.circle")
                }
                .popover(isPresented: $showFilters, arrowEdge: .bottom) { FilterForm(filters: $model.filters) }
            }
            .toggleStyle(.checkbox)
        }
    }

    private var filterTitle: String {
        let count = model.filters.activeCount
        return count == 0 ? String(localized: "Filters") : String(localized: "Filters (\(count))")
    }

    private var recentMenu: some View {
        Menu {
            ForEach(model.recentFolders, id: \.self) { url in
                Button(url.path) { model.open(url) }
            }
            if model.recentFolders.isEmpty { Text("No recent folders") }
        } label: {
            Image(systemName: "clock.arrow.circlepath")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Recent folders")
    }
}

private struct FilterForm: View {
    @Binding var filters: FilterInputs

    var body: some View {
        Form {
            TextField("Extensions", text: $filters.extensions, prompt: Text(verbatim: "jpg, psd, ai"))
            HStack {
                TextField("Size from (MB)", text: $filters.minMB)
                TextField("to (MB)", text: $filters.maxMB)
            }
            HStack {
                Toggle("Modified after", isOn: $filters.useModifiedAfter)
                DatePicker("", selection: $filters.modifiedAfter, displayedComponents: .date)
                    .labelsHidden().disabled(!filters.useModifiedAfter)
            }
            HStack {
                Toggle("Modified before", isOn: $filters.useModifiedBefore)
                DatePicker("", selection: $filters.modifiedBefore, displayedComponents: .date)
                    .labelsHidden().disabled(!filters.useModifiedBefore)
            }
            TextField("Finder tag", text: $filters.tag, prompt: Text("e.g. Red"))
            Text("Extension and size filters list files only.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Clear filters") { filters = FilterInputs() }
        }
        .padding(14)
        .frame(width: 340)
    }
}
