import ProteusCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: SearchModel
    @ObservedObject private var inbox = FolderInbox.shared
    @State private var confirmRename = false
    @State private var confirmTrash = false
    @State private var confirmUndo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScopeForm(model: model)
            Picker("", selection: $model.mode) {
                Text("Find & Replace").tag(SearchModel.Mode.findReplace)
                Text("Batch Rename").tag(SearchModel.Mode.batch)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 360)
            ResultsTable(model: model)
            Group {
                switch model.mode {
                case .findReplace: FindReplacePanel(model: model)
                case .batch: BatchRulesPanel(model: model)
                }
            }
            ActionBar(model: model, confirmRename: $confirmRename, confirmTrash: $confirmTrash,
                      confirmUndo: $confirmUndo)
            statusLine
        }
        .padding(16)
        .frame(minWidth: 920, minHeight: 660)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.open(url)
            return true
        }
        .onReceive(inbox.$pending.compactMap { $0 }) { url in
            model.open(url)
            inbox.pending = nil
        }
        .confirmationDialog("Rename (\(model.renameTargets.count))?", isPresented: $confirmRename) {
            Button("Rename") { Task { await model.renameSelected() } }
        } message: {
            Text(verbatim: renameMessage)
        }
        .confirmationDialog("Move to Trash (\(model.selectedItems.count))?", isPresented: $confirmTrash) {
            Button("Move to Trash", role: .destructive) { Task { await model.trashSelected() } }
        } message: {
            Text("You can restore them from the Trash, or with Undo.")
        }
        .confirmationDialog("Undo the last action (\(model.lastJournal?.entries.count ?? 0))?",
                            isPresented: $confirmUndo) {
            Button("Undo") { Task { await model.undoLast() } }
        } message: {
            Text("Every item goes back to its previous name and place. Anything changed since is left alone.")
        }
    }

    private var renameMessage: String {
        let blocked = model.blockedSteps.count
        let note = blocked == 0 ? "" : "\n\n" + String(localized: "Blocked, will be left alone: \(blocked)")
        return model.renameExamples + note + "\n\n" + String(localized: "You can undo this afterwards.")
    }

    private var statusLine: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                if model.isBusy { ProgressView().controlSize(.small) }
                Text(verbatim: model.status).font(.callout)
            }
            ScrollView {
                VStack(alignment: .leading) {
                    ForEach(model.failures, id: \.self) { failure in
                        Text(verbatim: failure).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .frame(maxHeight: model.failures.isEmpty ? 0 : 60)
        }
    }
}
