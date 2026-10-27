import Foundation
import ProteusCore

/// The rename plan: what each tab proposes, and carrying it out.
extension SearchModel {
    var renameTargets: [RenameStep] { plan.filter(\.isChange) }
    var blockedSteps: [RenameStep] { plan.filter { $0.problem != nil } }

    func step(for item: FoundItem) -> RenameStep? { planByID[item.id] }

    /// A few "old → new" lines for the confirmation dialog.
    var renameExamples: String {
        renameTargets.prefix(3).map { "\($0.item.name) → \($0.newName)" }.joined(separator: "\n")
    }

    var planSummary: String {
        var parts = [String(localized: "To rename: \(renameTargets.count)")]
        let numbered = plan.count { $0.numbered && $0.isChange }
        if numbered > 0 { parts.append(String(localized: "numbered to avoid a clash: \(numbered)")) }
        if !blockedSteps.isEmpty { parts.append(String(localized: "blocked: \(blockedSteps.count)")) }
        return parts.joined(separator: " · ")
    }

    func replan() {
        guard let searched else { return setPlan([]) }
        let selected = selectedItems
        let proposals: [(item: FoundItem, name: String)]
        switch mode {
        case .findReplace:
            proposals = selected.map {
                (item: $0, name: searched.proposedName(for: $0, replacement: replacement,
                                                       keepExtension: keepExtension, transform: transform))
            }
        case .batch:
            let positions = BatchRenamer.positions(for: selected, restartPerFolder: restartNumbering)
            proposals = zip(selected, positions).map { item, position in
                (item: item, name: BatchRenamer.name(for: item, rules: rules, position: position,
                                                     taken: takenDates[item.id]))
            }
        }
        setPlan(RenamePlanner.plan(proposals, numberClashes: mode == .batch && numberClashes))
    }

    func rulesChanged() {
        replan()
        loadTakenDatesIfNeeded()
    }

    /// Reads EXIF dates once per search, off the main thread, and only when a
    /// date row asks for them.
    func loadTakenDatesIfNeeded() {
        let needsDates = mode == .batch && rules.contains { $0.kind == .date && $0.dateSource == .taken }
        let missing = items.filter { !$0.isDirectory && !datesTried.contains($0.id) }
        guard needsDates, !missing.isEmpty, !isBusy else { return }
        let mine = generation
        // Busy while reading, so Rename cannot confirm a plan the dates are about to change.
        isBusy = true
        Task {
            defer { isBusy = false }
            let found = await Task.detached {
                Dictionary(uniqueKeysWithValues: missing.compactMap { item in
                    PhotoDate.read(item.url).map { (item.id, $0) }
                })
            }.value
            guard mine == generation else { return }
            datesTried.formUnion(missing.map(\.id))
            takenDates.merge(found) { $1 }
            replan()
        }
    }

    func addRule(after rule: BatchRule? = nil, kind: BatchRule.Kind = .text) {
        let index = rule.flatMap { current in rules.firstIndex { $0.id == current.id } }.map { $0 + 1 } ?? rules.count
        rules.insert(.starter(kind), at: index)
    }

    func removeRule(_ rule: BatchRule) {
        rules.removeAll { $0.id == rule.id }
    }

    func renameSelected() async {
        guard canAct else { return }
        let steps = plan
        await perform({ String(localized: "Renamed: \($0)") }) { FileActions.apply(steps) }
    }
}
