import Foundation
import Testing
@testable import ContextBank

@Suite struct ContextFileLocatorTests {
    @Test func findsFilesAscendingToRootClosestFirst() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("symaira-ctx-\(UUID().uuidString)", isDirectory: true)
        let sub = root.appendingPathComponent("src/feature", isDirectory: true)
        try fm.createDirectory(at: sub, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        try "root rules".write(to: root.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)
        try "root agents".write(to: root.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)
        try "feature rules".write(to: sub.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)

        let files = ContextFileLocator().locate(in: sub, ascendingTo: root)
        #expect(files.map(\.kind) == [.claude, .claude, .agents])
        #expect(files[0].url.standardizedFileURL.deletingLastPathComponent().path
            == sub.standardizedFileURL.path)
    }

    @Test func stopsAtGitRepositoryRootWithoutExplicitRoot() throws {
        let fm = FileManager.default
        let outer = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("symaira-ctx-\(UUID().uuidString)", isDirectory: true)
        let repo = outer.appendingPathComponent("repo", isDirectory: true)
        try fm.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: outer) }

        // A file ABOVE the repo root must not leak into the results.
        try "outside".write(to: outer.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)
        try "inside".write(to: repo.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)

        let files = ContextFileLocator().locate(in: repo)
        #expect(files.map(\.kind) == [.agents])
    }
}
