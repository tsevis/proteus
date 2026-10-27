import ProteusCore
import SwiftUI

struct ContentView: View {
    @StateObject private var model = SearchModel()
    @State private var confirmRename = false
    @State private var confirmTrash = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            searchForm
            resultsTable
            actionBar
            statusLine
        }
        .padding(16)
        .frame(minWidth: 820, minHeight: 520)
        .confirmationDialog("Rename (\(model.renameTargets.count))?",
                            isPresented: $confirmRename) {
            Button("Rename") { Task { await model.renameSelected() } }
        } message: {
            Text(verbatim: "«\(model.searched?.term ?? "")» → «\(model.replacement)»\n\n\(model.renameExamples)")
        }
        .confirmationDialog("Move to Trash (\(model.trashTargets.count))?",
                            isPresented: $confirmTrash) {
            Button("Move to Trash", role: .destructive) { Task { await model.trashSelected() } }
        } message: {
            Text("You can restore them from the Trash.")
        }
    }

    private var searchForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Folder…") { model.chooseFolder() }
                Group {
                    if let path = model.folder?.path { Text(verbatim: path) } else { Text("No folder") }
                }
                .foregroundStyle(model.folder == nil ? .secondary : .primary)
                .lineLimit(1).truncationMode(.middle)
            }
            HStack {
                TextField("Name contains… (e.g. Pete)", text: $model.term)
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
            }
            .toggleStyle(.checkbox)
        }
    }

    private var resultsTable: some View {
        Table(model.items) {
            TableColumn("") { item in
                Toggle("", isOn: selectionBinding(for: item)).labelsHidden()
            }
            .width(24)
            TableColumn("Name") { item in
                Label(item.name, systemImage: item.isDirectory ? "folder" : "doc")
            }
            TableColumn("New name") { item in
                let newName = model.newName(for: item)
                Text(newName).foregroundStyle(newName == item.name ? .secondary : .primary)
            }
            TableColumn("Location") { item in
                Text(model.relativeLocation(of: item)).foregroundStyle(.secondary)
            }
        }
    }

    private var actionBar: some View {
        HStack {
            TsevisMark()
                .padding(.trailing, 8)
            Button("All") { model.selectAll() }
            Button("None") { model.selectNone() }
            Spacer()
            TextField("Replace with… (e.g. MayorPete)", text: $model.replacement)
                .frame(maxWidth: 280)
            Button("Rename") { confirmRename = true }
                .disabled(!model.canAct || model.renameTargets.isEmpty)
            Button("Move to Trash", role: .destructive) { confirmTrash = true }
                .disabled(!model.canAct)
        }
    }

    private var statusLine: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                if model.isBusy { ProgressView().controlSize(.small) }
                Text(verbatim: model.status).font(.callout)
            }
            ForEach(model.failures, id: \.self) { failure in
                Text(verbatim: failure).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func selectionBinding(for item: FoundItem) -> Binding<Bool> {
        Binding(
            get: { model.selection.contains(item.id) },
            set: { isOn in
                if isOn { model.selection.insert(item.id) } else { model.selection.remove(item.id) }
            }
        )
    }
}
