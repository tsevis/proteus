import ProteusCore
import SwiftUI

struct ActionBar: View {
    @ObservedObject var model: SearchModel
    @Binding var confirmRename: Bool
    @Binding var confirmTrash: Bool
    @Binding var confirmUndo: Bool
    @State private var tagMode: TagMode?
    @State private var tagText = ""

    enum TagMode { case add, remove }

    var body: some View {
        HStack {
            TsevisMark()
                .padding(.trailing, 8)
            Button("All") { model.selectAll() }
            Button("None") { model.selectNone() }
            Spacer()
            if model.mode == .findReplace, model.searched != nil {
                Text(verbatim: model.planSummary).font(.caption).foregroundStyle(.secondary)
            }
            Button("Undo") { confirmUndo = true }
                .disabled(!model.canUndo)
                .help("Puts back the last rename or Trash")
            Menu("More") {
                Button("Add Finder Tag…") { tagMode = .add }
                Button("Remove Finder Tag…") { tagMode = .remove }
                Divider()
                Button("Export List as CSV…") { model.exportCSV() }
                    .disabled(model.items.isEmpty)
            }
            .disabled(model.isBusy)
            .fixedSize()
            Button("Rename") { confirmRename = true }
                .disabled(!model.canAct || model.renameTargets.isEmpty)
            Button("Move to Trash", role: .destructive) { confirmTrash = true }
                .disabled(!model.canTrash)
                .help(Text(verbatim: model.canAct && !model.canTrash
                      ? String(localized: "Type a name to search for first: an empty search lists everything.") : ""))
        }
        .alert(tagMode == .remove ? "Remove Finder Tag" : "Add Finder Tag", isPresented: tagBinding) {
            TextField("Tag", text: $tagText)
            Button(tagMode == .remove ? "Remove" : "Add") {
                let add = tagMode != .remove
                Task { await model.tagSelected(tagText, add: add) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Applies to the checked items (\(model.selectedItems.count)).")
        }
    }

    private var tagBinding: Binding<Bool> {
        Binding(get: { tagMode != nil }, set: { if !$0 { tagMode = nil } })
    }
}
