import Foundation
import Testing
@testable import SymairaUI
@testable import WorktreeKit

// MARK: - WorktreeStore pure logic

/// Tests for the side-effect-free surface of `WorktreeStore`: task-ID
/// validation, repository naming, and relative-age formatting. No git
/// subprocesses, no NSApplication, no rendering.
@Suite @MainActor struct WorktreeStoreLogicTests {
    private func makeStore(repoPath: String = "/tmp/symaira-test-repo") -> WorktreeStore {
        WorktreeStore(repositoryURL: URL(fileURLWithPath: repoPath, isDirectory: true))
    }

    // MARK: - validateTaskID

    @Test func validTaskIDsPass() {
        let store = makeStore()
        #expect(store.validateTaskID("123").isSuccess)
        #expect(store.validateTaskID("feature-fix-42").isSuccess)
        #expect(store.validateTaskID("abc_123.5").isSuccess)
    }

    @Test func emptyTaskIDFails() {
        let store = makeStore()
        #expect(failureCase(store.validateTaskID("")) == .empty)
    }

    @Test func overlongTaskIDFails() {
        let store = makeStore()
        let long = String(repeating: "a", count: TaskIDValidator.maxLength + 1)
        #expect(failureCase(store.validateTaskID(long)) == .tooLong(maxLength: TaskIDValidator.maxLength))
    }

    @Test func pathSeparatorsAreRejected() {
        let store = makeStore()
        #expect(failureCase(store.validateTaskID("a/b")) == .pathSeparator)
        #expect(failureCase(store.validateTaskID("a\\b")) == .pathSeparator)
        #expect(failureCase(store.validateTaskID("a/../b")) == .pathSeparator)
    }

    @Test func dotSegmentsAreRejected() {
        let store = makeStore()
        #expect(failureCase(store.validateTaskID("..")) == .dotSegment)
        #expect(failureCase(store.validateTaskID(".")) == .dotSegment)
        // Slash-containing IDs fail the path-separator check before the
        // dot-segment check is reached.
        #expect(failureCase(store.validateTaskID("./x")) == .pathSeparator)
        #expect(failureCase(store.validateTaskID("x/..")) == .pathSeparator)
    }

    @Test func invalidCharactersAreRejected() {
        let store = makeStore()
        #expect(failureCase(store.validateTaskID("hello world")) == .invalidCharacter(" "))
        #expect(failureCase(store.validateTaskID("task#1")) == .invalidCharacter("#"))
    }

    // MARK: - repositoryName

    @Test func repositoryNameIsLastPathComponent() {
        let store = makeStore(repoPath: "/Users/me/code/my-project")
        #expect(store.repositoryName == "my-project")
    }

    @Test func repositoryNameHandlesTrailingSlash() {
        let store = makeStore(repoPath: "/Users/me/code/my-project/")
        #expect(store.repositoryName == "my-project")
    }

    // MARK: - age formatting

    @Test func ageIsJustNowForFreshDirectories() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore()
        let worktree = Worktree(taskID: "1", path: dir, branch: "symaira/task-1")
        #expect(store.age(worktree) == "just now")
    }

    @Test func ageReportsMinutesHoursAndDays() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore()

        let cases: [(TimeInterval, String)] = [
            (5 * 60, "5m ago"),
            (2 * 3600, "2h ago"),
            (3 * 86400, "3d ago"),
        ]
        for (ageInterval, expected) in cases {
            let old = Date().addingTimeInterval(-ageInterval)
            try FileManager.default.setAttributes(
                [.creationDate: old],
                ofItemAtPath: dir.path
            )
            let worktree = Worktree(taskID: "1", path: dir, branch: "symaira/task-1")
            #expect(store.age(worktree) == expected, "expected '\(expected)' for age \(ageInterval)s")
        }
    }

    @Test func ageIsUnknownForMissingPaths() {
        let store = makeStore()
        let missing = Worktree(
            taskID: "1",
            path: URL(fileURLWithPath: "/nonexistent/symaira-test-path"),
            branch: "symaira/task-1"
        )
        #expect(store.age(missing) == "unknown")
    }

    // MARK: - dirty cache default

    @Test func dirtyCacheDefaultsToFalseBeforeRefresh() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore()
        let worktree = Worktree(taskID: "1", path: dir, branch: "symaira/task-1")
        // No `refreshDirtyState(for:)` call yet — must not block or touch git.
        #expect(!store.isDirtyCached(worktree))
    }

    // MARK: - Helpers

    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorktreeStoreLogicTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

private extension Result where Failure == TaskIDError {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

private extension WorktreeStoreLogicTests {
    func failureCase(_ result: Result<Void, TaskIDError>) -> TaskIDError? {
        if case .failure(let error) = result { return error }
        return nil
    }
}
