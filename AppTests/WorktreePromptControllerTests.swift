import XCTest
import SymairaUI
@testable import WorktreeKit
@testable import SymairaTerminal

/// Tests for the worktree-creation prompt flow extracted from AppDelegate.
@MainActor
final class WorktreePromptControllerTests: XCTestCase {

    func testPromptReturnsWorktreeOnSuccess() {
        var createdTaskID: String?
        let expectedWorktree = Worktree(taskID: "TASK-123", path: URL(fileURLWithPath: "/tmp/wt"), branch: "wt/TASK-123")

        let controller = WorktreePromptController(alertRunner: { _ in .alertFirstButtonReturn })
        controller.promptInput.stringValue = "TASK-123"

        let store = makeStore()

        let result = controller.promptForWorktree(worktreeStore: store) { taskID in
            createdTaskID = taskID
            return expectedWorktree
        }

        XCTAssertEqual(result?.taskID, "TASK-123")
        XCTAssertEqual(createdTaskID, "TASK-123")
    }

    func testPromptReturnsNilOnCancel() {
        var createCalled = false

        let controller = WorktreePromptController(alertRunner: { _ in .alertSecondButtonReturn })

        let store = makeStore()

        let result = controller.promptForWorktree(worktreeStore: store) { _ in
            createCalled = true
            return Worktree(taskID: "X", path: URL(fileURLWithPath: "/tmp"), branch: "x")
        }

        XCTAssertNil(result)
        XCTAssertFalse(createCalled, "Create closure must not be called on cancel")
    }

    func testPromptShowsErrorOnEmptyInput() {
        var errorAlertShown = false

        let controller = WorktreePromptController(alertRunner: { alert in
            if alert.messageText.contains("Invalid Task ID") {
                errorAlertShown = true
            }
            return .alertFirstButtonReturn
        })
        controller.promptInput.stringValue = "   " // whitespace only

        let store = makeStore()

        let result = controller.promptForWorktree(worktreeStore: store) { _ in
            return Worktree(taskID: "X", path: URL(fileURLWithPath: "/tmp"), branch: "x")
        }

        XCTAssertNil(result)
        XCTAssertTrue(errorAlertShown, "An error alert should be shown for empty input")
    }

    func testPromptShowsErrorOnInvalidTaskID() {
        var errorAlertShown = false

        let controller = WorktreePromptController(alertRunner: { alert in
            if alert.messageText.contains("Invalid Task ID") {
                errorAlertShown = true
            }
            return .alertFirstButtonReturn
        })
        controller.promptInput.stringValue = "bad/task" // path separator

        let store = makeStore()

        let result = controller.promptForWorktree(worktreeStore: store) { _ in
            return Worktree(taskID: "X", path: URL(fileURLWithPath: "/tmp"), branch: "x")
        }

        XCTAssertNil(result)
        XCTAssertTrue(errorAlertShown, "An error alert should be shown for invalid task ID")
    }

    func testPromptShowsErrorAlertOnCreateFailure() {
        var errorAlertShown = false

        let controller = WorktreePromptController(alertRunner: { alert in
            if alert.messageText.contains("Error") || !alert.buttons.isEmpty && alert.buttons.count == 1 {
                errorAlertShown = true
            }
            return .alertFirstButtonReturn
        })
        controller.promptInput.stringValue = "BAD-TASK"

        let store = makeStore()

        let result = controller.promptForWorktree(worktreeStore: store) { _ in
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "creation failed"])
        }

        XCTAssertNil(result)
        XCTAssertTrue(errorAlertShown, "An error alert should be shown when creation fails")
    }

    func testPromptShowsErrorWhenNotAGitRepo() {
        var repoErrorAlertShown = false

        let controller = WorktreePromptController(alertRunner: { alert in
            if alert.messageText.contains("Cannot Create Worktree") {
                repoErrorAlertShown = true
            }
            return .alertFirstButtonReturn
        })

        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("symaira-test-nonrepo-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let store = WorktreeStore(repositoryURL: tmpDir)

        let result = controller.promptForWorktree(worktreeStore: store) { _ in
            return Worktree(taskID: "X", path: URL(fileURLWithPath: "/tmp"), branch: "x")
        }

        XCTAssertNil(result)
        XCTAssertTrue(repoErrorAlertShown, "An error alert should be shown when cwd is not a git repo")
    }

    // MARK: - Helpers

    /// Creates a `WorktreeStore` backed by a throwaway git repository, so the
    /// `isGitRepository()` guard in `promptForWorktree` passes.
    private func makeStore() -> WorktreeStore {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("symaira-wt-prompt-test-\(UUID().uuidString)", isDirectory: true)
        let repo = base.appendingPathComponent("repo", isDirectory: true)
        try? FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["init", "-b", "main"]
        process.currentDirectoryURL = repo
        try? process.run()
        process.waitUntilExit()

        return WorktreeStore(repositoryURL: repo)
    }
}
