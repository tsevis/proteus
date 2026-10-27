import ProteusCore
import SwiftUI

/// Find & Replace: replace the found text, then optionally transform the name.
struct FindReplacePanel: View {
    @ObservedObject var model: SearchModel

    var body: some View {
        HStack(spacing: 12) {
            TextField("Replace with… (empty removes it)", text: $model.replacement)
                .frame(maxWidth: 320)
            Picker("Then", selection: $model.transform) {
                ForEach(NameTransform.allCases) { Text(verbatim: $0.title).tag($0) }
            }
            .frame(maxWidth: 320)
            Toggle("Keep extension", isOn: $model.keepExtension)
                .toggleStyle(.checkbox)
                .help("Leaves .jpg, .psd and the like exactly as they are.")
            Spacer()
        }
    }
}

/// Batch Rename: a stack of rows, as in Bridge, each one part of the new name.
struct BatchRulesPanel: View {
    @ObservedObject var model: SearchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach($model.rules) { $rule in
                        RuleRow(rule: $rule,
                                add: { model.addRule(after: rule) },
                                remove: model.rules.count > 1 ? { model.removeRule(rule) } : nil)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(minHeight: 34, maxHeight: 150)
            .fixedSize(horizontal: false, vertical: model.rules.count <= 3)
            HStack(spacing: 16) {
                Toggle("Number clashes", isOn: $model.numberClashes)
                    .help("Adds ' 2', ' 3'… when two items would get the same name. Off makes a clash block the item.")
                Toggle("Restart numbering in each folder", isOn: $model.restartNumbering)
                Spacer()
                Text(verbatim: model.planSummary).font(.caption).foregroundStyle(.secondary)
            }
            .toggleStyle(.checkbox)
        }
    }
}

private struct RuleRow: View {
    @Binding var rule: BatchRule
    let add: () -> Void
    let remove: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: $rule.kind) {
                ForEach(BatchRule.Kind.allCases, id: \.self) { Text(verbatim: $0.title).tag($0) }
            }
            .labelsHidden()
            .frame(width: 170)
            .onChange(of: rule.kind) { _, kind in rule = BatchRule.starter(kind).with(id: rule.id) }
            fields
            Spacer(minLength: 0)
            Button { remove?() } label: { Image(systemName: "minus") }
                .disabled(remove == nil)
            Button(action: add) { Image(systemName: "plus") }
        }
    }

    @ViewBuilder
    private var fields: some View {
        switch rule.kind {
        case .text:
            TextField("Text", text: $rule.text)
        case .currentName, .folderName, .sequenceLetter:
            EmptyView()
        case .sequenceNumber:
            TextField("Start", text: $rule.text).frame(width: 70)
            Stepper("Digits: \(rule.digits)", value: $rule.digits, in: 1...9).fixedSize()
        case .date:
            Picker("", selection: $rule.dateSource) {
                ForEach(BatchRule.DateSource.allCases, id: \.self) { Text(verbatim: $0.title).tag($0) }
            }
            .labelsHidden().frame(width: 140)
            TextField("Format", text: $rule.text, prompt: Text(verbatim: "yyyy-MM-dd")).frame(width: 160)
        case .replace:
            TextField("Find", text: $rule.text)
            TextField("Replace with", text: $rule.replacement)
        case .transform:
            Picker("", selection: $rule.transform) {
                ForEach(NameTransform.allCases) { Text(verbatim: $0.title).tag($0) }
            }
            .labelsHidden().frame(maxWidth: 300)
        case .newExtension:
            TextField("Extension", text: $rule.text, prompt: Text(verbatim: "jpg")).frame(width: 100)
        }
    }
}

private extension BatchRule {
    func with(id: UUID) -> BatchRule {
        var copy = self
        copy.id = id
        return copy
    }
}
