import Foundation
import Testing
@testable import WorktreeKit

/// Creates a throwaway git repo with one commit and returns (repo, container).
private func makeFixtureRepo() throws -> (repo: URL, container: URL) {
    let base = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("symaira-worktree-tests-\(UUID().uuidString)", isDirectory: true)
    let repo = base.appendingPathComponent("repo", isDirectory: true)
    let container = base.appendingPathComponent("worktrees", isDirectory: true)
    try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)

    let manager = WorktreeManager(repositoryURL: repo, containerURL: container)
    try manager.git(["init", "-b", "main"])
    try manager.git(["config", "user.email", "test@symaira.local"])
    try manager.git(["config", "user.name", "Test"])
    try "hello\n".write(to: repo.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
    try manager.git(["add", "."])
    try manager.git(["commit", "-m", "initial"])
    return (repo, container)
}

@Suite struct WorktreeManagerTests {
    @Test func createListDiffRemoveLifecycle() throws {
        let (repo, container) = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(at: container.deletingLastPathComponent()) }
        let manager = WorktreeManager(repositoryURL: repo, containerURL: container)

        let worktree = try manager.create(taskID: "abc123")
        #expect(worktree.branch == "symaira/task-abc123")
        #expect(FileManager.default.fileExists(atPath: worktree.path.appendingPathComponent("file.txt").path))

        let listed = try manager.list()
        #expect(listed.map(\.taskID) == ["abc123"])

        // Agent edits a file in isolation; the diff feeds the review panel.
        try "changed\n".write(
            to: worktree.path.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        let diff = try manager.diff(worktree)
        #expect(diff.contains("-hello"))
        #expect(diff.contains("+changed"))

        // Dirty worktrees need force; afterwards everything is gone.
        try manager.remove(worktree, deleteBranch: true, force: true)
        #expect(try manager.list().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: worktree.path.path))
    }

    @Test func gitFailureSurfacesStderr() throws {
        let (repo, container) = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(at: container.deletingLastPathComponent()) }
        let manager = WorktreeManager(repositoryURL: repo, containerURL: container)

        #expect(throws: WorktreeError.self) {
            try manager.git(["worktree", "remove", "/nonexistent/path"])
        }
    }
}
