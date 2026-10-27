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
        .confirmationDialog("Μετονομασία \(model.renameTargets.count) αντικειμένων;",
                            isPresented: $confirmRename) {
            Button("Μετονομασία") { Task { await model.renameSelected() } }
        } message: {
            Text("«\(model.searched?.term ?? "")» → «\(model.replacement)»\n\n\(model.renameExamples)")
        }
        .confirmationDialog("Μεταφορά \(model.trashTargets.count) αντικειμένων στον Κάδο;",
                            isPresented: $confirmTrash) {
            Button("Στον Κάδο", role: .destructive) { Task { await model.trashSelected() } }
        } message: {
            Text("Μπορείς να τα επαναφέρεις από τον Κάδο.")
        }
    }

    private var searchForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Φάκελος…") { model.chooseFolder() }
                Text(model.folder?.path ?? "Κανένας φάκελος")
                    .foregroundStyle(model.folder == nil ? .secondary : .primary)
                    .lineLimit(1).truncationMode(.middle)
            }
            HStack {
                TextField("Το όνομα περιέχει… (π.χ. Pete)", text: $model.term)
                    .onSubmit { Task { await model.search() } }
                Button("Αναζήτηση") { Task { await model.search() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canSearch)
            }
            HStack(spacing: 16) {
                Toggle("Αρχεία", isOn: $model.includeFiles)
                Toggle("Φάκελοι", isOn: $model.includeFolders)
                Toggle("Κρυφά", isOn: $model.includeHidden)
                Toggle("Πεζά/κεφαλαία", isOn: $model.caseSensitive)
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
            TableColumn("Όνομα") { item in
                Label(item.name, systemImage: item.isDirectory ? "folder" : "doc")
            }
            TableColumn("Νέο όνομα") { item in
                let newName = model.newName(for: item)
                Text(newName).foregroundStyle(newName == item.name ? .secondary : .primary)
            }
            TableColumn("Θέση") { item in
                Text(model.relativeLocation(of: item)).foregroundStyle(.secondary)
            }
        }
    }

    private var actionBar: some View {
        HStack {
            TsevisMark()
                .padding(.trailing, 8)
            Button("Όλα") { model.selectAll() }
            Button("Κανένα") { model.selectNone() }
            Spacer()
            TextField("Αντικατάσταση με… (π.χ. MayorPete)", text: $model.replacement)
                .frame(maxWidth: 280)
            Button("Μετονομασία") { confirmRename = true }
                .disabled(!model.canAct || model.renameTargets.isEmpty)
            Button("Στον Κάδο", role: .destructive) { confirmTrash = true }
                .disabled(!model.canAct)
        }
    }

    private var statusLine: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                if model.isBusy { ProgressView().controlSize(.small) }
                Text(model.status).font(.callout)
            }
            ForEach(model.failures, id: \.self) { failure in
                Text(failure).font(.caption).foregroundStyle(.red)
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
