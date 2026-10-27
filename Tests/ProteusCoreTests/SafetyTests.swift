import Foundation
import Testing
@testable import ProteusCore

/// A fresh folder of dummy files per test, removed afterwards.
final class Sandbox {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("proteus-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    @discardableResult
    func make(_ relative: String, folder: Bool = false) throws -> URL {
        let url = root.appendingPathComponent(relative)
        let fm = FileManager.default
        if folder {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        } else {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: url.path, contents: Data())
        }
        return url
    }

    func exists(_ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(relative).path)
    }

    func scan(_ term: String, regex: Bool = false) throws -> [FoundItem] {
        let matcher = try NameMatcher(term: term, caseSensitive: false, useRegex: regex)
        let options = ScanOptions(includeFiles: true, includeFolders: true, includeHidden: false)
        return try FileScanner.scan(root: root, matcher: matcher, options: options)
    }
}

@Suite struct ScannerSafety {
    let box: Sandbox
    init() throws { box = try Sandbox() }

    // Renaming files inside an app or a Photos/Final Cut library breaks it.
    @Test func doesNotLookInsidePackages() throws {
        try box.make("Pete.app/Contents/Resources/Pete.png")
        let found = try box.scan("Pete").map(\.name)
        #expect(found == ["Pete.app"])
    }
}

@Suite struct MatcherSafety {
    // A pattern like `x*` matches the empty string, so it selected every name
    // in the tree for the Trash and inserted the replacement between letters.
    @Test(arguments: ["x*", "^", "$", "(Pete)?", "\\b", "(?=a)"])
    func emptyMatchesSelectNothing(pattern: String) throws {
        let matcher = try NameMatcher(term: pattern, caseSensitive: false, useRegex: true)
        #expect(!matcher.matches("plain.doc"))
        #expect(matcher.replacing(in: "plain.doc", with: "-") == "plain.doc")
    }

    @Test func emptyMatchesAreLeftAloneBesideRealOnes() throws {
        let matcher = try NameMatcher(term: "x*", caseSensitive: false, useRegex: true)
        #expect(matcher.replacing(in: "axx.txt", with: "-") == "a-.t-t")
    }

    // Greek names written by other systems arrive decomposed (NFD).
    @Test func regexMatchesDecomposedGreek() throws {
        let matcher = try NameMatcher(term: "καλημέρα", caseSensitive: false, useRegex: true)
        #expect(matcher.matches("καλημέρα.txt".decomposedStringWithCanonicalMapping))
    }
}

@Suite struct RenameSafety {
    let box: Sandbox
    init() throws { box = try Sandbox() }

    // `Pete.txt` with an empty replacement would become the hidden file `.txt`.
    @Test func refusesToHideAFile() throws {
        try box.make("Pete.txt")
        let matcher = try NameMatcher(term: "Pete", caseSensitive: false, useRegex: false)
        let report = FileActions.rename(try box.scan("Pete"), matcher: matcher, replacement: "")
        #expect(report.succeeded == 0)
        #expect(report.failures.count == 1)
        #expect(box.exists("Pete.txt"))
    }

    // A folder renamed before its contents leaves the contents' paths stale.
    @Test func renamesFolderAndItsContentsTogether() throws {
        try box.make("Pete/sub/Pete notes.txt")
        let matcher = try NameMatcher(term: "Pete", caseSensitive: false, useRegex: false)
        let report = FileActions.rename(try box.scan("Pete"), matcher: matcher, replacement: "Mayor")
        #expect(report.failures.isEmpty)
        #expect(box.exists("Mayor/sub/Mayor notes.txt"))
    }

    // moveItem must never replace a file that already has the new name.
    @Test func neverOverwritesAnExistingFile() throws {
        try box.make("Pete.txt")
        let keep = try box.make("Mayor.txt")
        try Data("keep me".utf8).write(to: keep)
        let matcher = try NameMatcher(term: "Pete", caseSensitive: false, useRegex: false)
        let report = FileActions.rename(try box.scan("Pete"), matcher: matcher, replacement: "Mayor")
        #expect(report.failures.count == 1)
        #expect(try String(contentsOf: keep, encoding: .utf8) == "keep me")
        #expect(box.exists("Pete.txt"))
    }
}

@Suite struct StaleResults {
    let box: Sandbox
    init() throws { box = try Sandbox() }

    // A file swapped in after the search must not be renamed in its place.
    @Test func refusesAFileReplacedSinceTheSearch() throws {
        let original = try box.make("Pete.txt")
        let found = try box.scan("Pete")
        try FileManager.default.removeItem(at: original)
        try Data("newcomer".utf8).write(to: original)
        let matcher = try NameMatcher(term: "Pete", caseSensitive: false, useRegex: false)
        let report = FileActions.rename(found, matcher: matcher, replacement: "Mayor")
        #expect(report.succeeded == 0)
        #expect(box.exists("Pete.txt"))
    }
}

@Suite struct HiddenSafety {
    let box: Sandbox
    init() throws { box = try Sandbox() }

    // Renaming inside .git corrupts the repository, even with hidden files shown.
    @Test func neverLooksInsideGit() throws {
        try box.make(".git/refs/heads/pete")
        let matcher = try NameMatcher(term: "pete", caseSensitive: false, useRegex: false)
        let options = ScanOptions(includeFiles: true, includeFolders: true, includeHidden: true)
        #expect(try FileScanner.scan(root: box.root, matcher: matcher, options: options).isEmpty)
    }
}
