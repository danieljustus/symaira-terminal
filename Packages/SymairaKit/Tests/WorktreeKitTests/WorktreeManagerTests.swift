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
    /// Regression: draining stdout fully before stderr deadlocks once the second
    /// stream fills its ~64 KB pipe buffer. This process writes ~200 KB to each
    /// stream; the concurrent drain in `run` must complete without hanging.
    @Test func runDoesNotDeadlockOnLargeDualStreams() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "yes x | head -c 200000; yes y | head -c 200000 1>&2"]
        let (out, err, status) = try WorktreeManager.run(process)
        #expect(status == 0)
        #expect(out.count == 200000)
        #expect(err.count == 200000)
    }

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

    @Test func handoffPackageLifecycle() throws {
        let (repo, container) = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(at: container.deletingLastPathComponent()) }
        let manager = WorktreeManager(repositoryURL: repo, containerURL: container)

        let sourceWT = try manager.create(taskID: "source1")
        try "handoff text\n".write(
            to: sourceWT.path.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)

        let package = try manager.createHandoffPackage(from: sourceWT)
        #expect(package.sourceTaskID == "source1")
        #expect(!package.gitDiffCompressedBase64.isEmpty)
        #expect(package.summary.contains("file.txt"))

        let targetWT = try manager.create(taskID: "target1")
        try manager.applyHandoffPackage(package, to: targetWT)

        let targetContent = try String(contentsOf: targetWT.path.appendingPathComponent("file.txt"), encoding: .utf8)
        #expect(targetContent == "handoff text\n")
    }
}
