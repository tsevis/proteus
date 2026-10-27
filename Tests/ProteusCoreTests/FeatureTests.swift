import Foundation
import Testing
@testable import ProteusCore

@Suite struct UndoSafety {
    let box: Sandbox
    init() throws { box = try Sandbox() }

    private func renamePete(to replacement: String) throws -> ActionOutcome {
        let matcher = try NameMatcher(term: "Pete", caseSensitive: false, useRegex: false)
        let proposals = try box.scan("Pete").map { (item: $0, name: matcher.replacing(in: $0.name, with: replacement)) }
        return FileActions.apply(RenamePlanner.plan(proposals, numberClashes: false))
    }

    // Undoing a child before its renamed parent finds the child's path gone.
    @Test func undoRestoresAFolderAndItsContents() throws {
        try box.make("Pete/sub/Pete notes.txt")
        let outcome = try renamePete(to: "Mayor")
        #expect(box.exists("Mayor/sub/Mayor notes.txt"))
        let report = outcome.journal.undo()
        #expect(report.failures.isEmpty)
        #expect(box.exists("Pete/sub/Pete notes.txt"))
    }

    // Undo must never replace a file that has since taken the old name.
    @Test func undoNeverOverwritesANewcomer() throws {
        try box.make("Pete.txt")
        let outcome = try renamePete(to: "Mayor")
        let newcomer = try box.make("Pete.txt")
        try Data("newcomer".utf8).write(to: newcomer)
        let report = outcome.journal.undo()
        #expect(report.succeeded == 0)
        #expect(try String(contentsOf: newcomer, encoding: .utf8) == "newcomer")
        #expect(box.exists("Mayor.txt"))
    }

    @Test func journalSurvivesSaving() throws {
        try box.make("Pete.txt")
        let outcome = try renamePete(to: "Mayor")
        let file = box.root.appendingPathComponent("journal/last.json")
        try outcome.journal.save(to: file)
        #expect(try Journal.load(from: file)?.undo().succeeded == 1)
        #expect(box.exists("Pete.txt"))
    }
}

@Suite struct PlannerSafety {
    let box: Sandbox
    init() throws { box = try Sandbox() }

    // Two selected files given the same name: the second would fail mid-batch.
    @Test func flagsTwoItemsWantingOneName() throws {
        try box.make("a.txt")
        try box.make("b.txt")
        let items = try box.scan("")
        let steps = RenamePlanner.plan(items.map { (item: $0, name: "same.txt") }, numberClashes: false)
        #expect(steps.filter(\.isChange).count == 1)
        #expect(steps.contains { $0.problem == .duplicateInBatch("same.txt") })
    }

    @Test func numbersClashesWhenAsked() throws {
        try box.make("a.txt")
        try box.make("b.txt")
        try box.make("same.txt")
        let items = try box.scan("").filter { $0.name != "same.txt" }
        let steps = RenamePlanner.plan(items.map { (item: $0, name: "same.txt") }, numberClashes: true)
        #expect(steps.map(\.newName) == ["same 2.txt", "same 3.txt"])
    }

    @Test func keepsTheExtensionOutOfReplace() throws {
        try box.make("jpg photo.jpg")
        let item = try #require(try box.scan("jpg").first)
        let matcher = try NameMatcher(term: "jpg", caseSensitive: false, useRegex: false)
        #expect(matcher.proposedName(for: item, replacement: "png", keepExtension: true, transform: .none)
            == "png photo.jpg")
    }
}

@Suite struct Transforms {
    @Test(arguments: [
        ("Γιάννης Logo Final.PNG", "giannis-logo-final.png"),
        ("Café   au lait!.jpg", "cafe-au-lait.jpg"),
        ("Україна 2026.pdf", "ukraina-2026.pdf"),
    ])
    func slug(name: String, expected: String) {
        #expect(NameTransform.slug.apply(toName: name, isDirectory: false) == expected)
    }

    @Test func greeklish() {
        #expect(NameTransform.latin.apply(to: "Θέα από Μπαλκόνι ΟΥΡΑΝΟΣ") == "Thea apo Balkoni OURANOS")
    }

    @Test func folderNamesHaveNoExtension() {
        #expect(NameTransform.uppercase.apply(toName: "v1.final", isDirectory: true) == "V1.FINAL")
    }
}

@Suite struct BatchNaming {
    @Test func restartsNumberingInEachFolder() {
        let items = ["/r/a/1.jpg", "/r/a/2.jpg", "/r/b/3.jpg"].map {
            FoundItem(url: URL(fileURLWithPath: $0), isDirectory: false, depth: 2, fileID: nil)
        }
        #expect(BatchRenamer.positions(for: items, restartPerFolder: true) == [0, 1, 0])
        #expect(BatchRenamer.positions(for: items, restartPerFolder: false) == [0, 1, 2])
    }

    @Test func buildsANameFromRows() {
        let item = FoundItem(url: URL(fileURLWithPath: "/r/Trip/IMG 0001.JPG"), isDirectory: false, depth: 2, fileID: nil)
        let rules = [BatchRule(kind: .folderName), BatchRule(kind: .text, text: "_"),
                     BatchRule(kind: .sequenceNumber, text: "1", digits: 3),
                     BatchRule(kind: .newExtension, text: ".jpg")]
        #expect(BatchRenamer.name(for: item, rules: rules, position: 4) == "Trip_005.jpg")
    }
}

@Suite struct IndexHits {
    let box: Sandbox
    init() throws { box = try Sandbox() }

    // Spotlight indexes inside packages and .git; the folder walk never does.
    @Test func dropsHitsInsidePackagesAndGit() throws {
        let inPackage = try box.make("Pete.app/Contents/Pete.png")
        let inGit = try box.make(".git/Pete")
        let real = try box.make("Pete.txt")
        let matcher = try NameMatcher(term: "Pete", caseSensitive: false, useRegex: false)
        let options = ScanOptions(includeFiles: true, includeFolders: true, includeHidden: true)
        let found = FileScanner.filterIndexHits([inPackage.path, inGit.path, real.path, "/etc/Pete"],
                                                root: box.root, matcher: matcher, options: options)
        #expect(found.map(\.name) == ["Pete.txt"])
    }
}

@Suite struct Exports {
    @Test func quotesFieldsThatNeedIt() {
        #expect(CSVExport.document([["a,b", "say \"hi\"", "plain"]]) == "\"a,b\",\"say \"\"hi\"\"\",plain\r\n")
    }
}

@Suite struct ReviewFindings {
    let box: Sandbox
    init() throws { box = try Sandbox() }

    // A Photos library dropped on the window must not be opened up for renaming.
    @Test func refusesAPackageAsTheRoot() throws {
        try box.make("Lib.app/Contents/Info.plist")
        let matcher = try NameMatcher(term: "", caseSensitive: false, useRegex: false)
        let options = ScanOptions(includeFiles: true, includeFolders: true, includeHidden: false)
        #expect(throws: (any Error).self) {
            try FileScanner.scan(root: box.root.appendingPathComponent("Lib.app/Contents"), matcher: matcher, options: options)
        }
    }

    // Numbering a 255-byte clash must not promise a name the disk refuses.
    @Test func numberedNameStaysWithinTheLimit() throws {
        let long = String(repeating: "a", count: 251) + ".txt"
        try box.make(long)
        try box.make("b.txt")
        let item = try #require(try box.scan("b.txt").first)
        let step = try #require(RenamePlanner.plan([(item: item, name: long)], numberClashes: true).first)
        #expect(step.newName.utf8.count <= 255 || step.problem != nil)
    }
}

@Suite struct AddedByHand {
    let box: Sandbox
    init() throws { box = try Sandbox() }

    // A folder added by hand and a file found inside it by a search must still
    // be renamed deepest first, or the file's path is gone by its turn.
    @Test func handPickedFolderAndSearchedChildRenameTogether() throws {
        let folder = try box.make("Pete", folder: true)
        try box.make("Pete/Pete.txt")
        let child = try box.scan("Pete").filter { !$0.isDirectory }
        let picked = FileScanner.items(for: [folder]).items
        let steps = RenamePlanner.plan((picked + child).map { (item: $0, name: $0.name.replacingOccurrences(of: "Pete", with: "Mayor")) },
                                       numberClashes: false)
        let report = FileActions.apply(steps).report
        #expect(report.failures.isEmpty)
        #expect(box.exists("Mayor/Mayor.txt"))
    }

    @Test func refusesItemsInsidePackagesAndGit() throws {
        let inPackage = try box.make("Lib.app/Contents/Info.plist")
        let inGit = try box.make(".git/config")
        let fine = try box.make("fine.txt")
        let result = FileScanner.items(for: [inPackage, inGit, fine])
        #expect(result.items.map(\.name) == ["fine.txt"])
        #expect(result.refused.count == 2)
    }
}

@Suite struct Relocation {
    let box: Sandbox
    init() throws { box = try Sandbox() }

    // A hand-picked file inside a renamed folder must be found again at its
    // new path after the rename, and at the old one after Undo.
    @Test func followsAFileThroughRenameAndUndo() throws {
        try box.make("Pete/Pete.txt")
        let matcher = try NameMatcher(term: "Pete", caseSensitive: false, useRegex: false)
        let found = try box.scan("Pete")
        let outcome = FileActions.apply(RenamePlanner.plan(
            found.map { (item: $0, name: matcher.replacing(in: $0.name, with: "Mayor")) }, numberClashes: false))
        let picked = box.root.appendingPathComponent("Pete/Pete.txt").standardizedFileURL.path
        let moved = outcome.journal.relocate(picked, undoing: false)
        #expect(FileManager.default.fileExists(atPath: moved))
        _ = outcome.journal.undo()
        #expect(outcome.journal.relocate(moved, undoing: true) == picked)
    }
}
