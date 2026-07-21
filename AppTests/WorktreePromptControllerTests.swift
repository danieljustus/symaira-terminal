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

        let result = controller.promptForWorktree(worktreeStore: makeStore()) { taskID in
            createdTaskID = taskID
            return expectedWorktree
        }

        XCTAssertEqual(result?.taskID, "TASK-123")
        XCTAssertEqual(createdTaskID, "TASK-123")
    }

    func testPromptReturnsNilOnCancel() {
        var createCalled = false

        let controller = WorktreePromptController(alertRunner: { _ in .alertSecondButtonReturn })

        let result = controller.promptForWorktree(worktreeStore: makeStore()) { _ in
            createCalled = true
            return Worktree(taskID: "X", path: URL(fileURLWithPath: "/tmp"), branch: "x")
        }

        XCTAssertNil(result)
        XCTAssertFalse(createCalled, "Create closure must not be called on cancel")
    }

    func testPromptReturnsNilOnEmptyInput() {
        var createCalled = false

        let controller = WorktreePromptController(alertRunner: { _ in .alertFirstButtonReturn })
        controller.promptInput.stringValue = "   " // whitespace only

        let result = controller.promptForWorktree(worktreeStore: makeStore()) { _ in
            createCalled = true
            return Worktree(taskID: "X", path: URL(fileURLWithPath: "/tmp"), branch: "x")
        }

        XCTAssertNil(result)
        XCTAssertFalse(createCalled, "Create closure must not be called for empty input")
    }

    func testPromptShowsErrorAlertOnCreateFailure() {
        var errorAlertShown = false

        let controller = WorktreePromptController(alertRunner: { alert in
            // If the alert's message is about an error, it's the error alert
            if alert.messageText.contains("Error") || !alert.buttons.isEmpty && alert.buttons.count == 1 {
                errorAlertShown = true
            }
            return .alertFirstButtonReturn
        })
        controller.promptInput.stringValue = "BAD-TASK"

        let result = controller.promptForWorktree(worktreeStore: makeStore()) { _ in
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "creation failed"])
        }

        XCTAssertNil(result)
        XCTAssertTrue(errorAlertShown, "An error alert should be shown when creation fails")
    }

    // MARK: - Helpers

    private func makeStore() -> WorktreeStore {
        WorktreeStore(repositoryURL: URL(fileURLWithPath: NSHomeDirectory()))
    }
}
