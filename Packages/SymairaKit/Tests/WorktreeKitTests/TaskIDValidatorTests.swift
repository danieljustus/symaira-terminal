import XCTest
@testable import WorktreeKit

final class TaskIDValidatorTests: XCTestCase {
    private var validator: TaskIDValidator!

    override func setUp() {
        super.setUp()
        validator = TaskIDValidator()
    }

    func testAcceptsSimpleID() {
        XCTAssertNoThrow(try validator.validate("task-123"))
    }

    func testAcceptsIDWithDots() {
        XCTAssertNoThrow(try validator.validate("task.v1.0"))
    }

    func testAcceptsIDWithUnderscores() {
        XCTAssertNoThrow(try validator.validate("my_task_name"))
    }

    func testAcceptsIDWithHyphens() {
        XCTAssertNoThrow(try validator.validate("my-task-name"))
    }

    func testRejectsEmptyID() {
        XCTAssertThrowsError(try validator.validate("")) { error in
            XCTAssertEqual(error as? TaskIDError, TaskIDError.empty)
        }
    }

    func testRejectsTooLongID() {
        let longID = String(repeating: "a", count: TaskIDValidator.maxLength + 1)
        XCTAssertThrowsError(try validator.validate(longID)) { error in
            if case TaskIDError.tooLong(let max) = error {
                XCTAssertEqual(max, TaskIDValidator.maxLength)
            } else {
                XCTFail("Expected tooLong error")
            }
        }
    }

    func testRejectsPathSeparatorForwardSlash() {
        XCTAssertThrowsError(try validator.validate("task/name")) { error in
            XCTAssertEqual(error as? TaskIDError, TaskIDError.pathSeparator)
        }
    }

    func testRejectsPathSeparatorBackslash() {
        XCTAssertThrowsError(try validator.validate("task\\name")) { error in
            XCTAssertEqual(error as? TaskIDError, TaskIDError.pathSeparator)
        }
    }

    func testRejectsDotSegmentDoubleDot() {
        XCTAssertThrowsError(try validator.validate("task..name")) { error in
            XCTAssertEqual(error as? TaskIDError, TaskIDError.dotSegment)
        }
    }

    func testRejectsDotSegmentSingleDot() {
        XCTAssertThrowsError(try validator.validate(".")) { error in
            XCTAssertEqual(error as? TaskIDError, TaskIDError.dotSegment)
        }
    }

    func testRejectsDotPrefix() {
        XCTAssertThrowsError(try validator.validate(".hidden")) { error in
            XCTAssertEqual(error as? TaskIDError, TaskIDError.invalidBranchName)
        }
    }

    func testRejectsHyphenPrefix() {
        XCTAssertThrowsError(try validator.validate("-invalid")) { error in
            XCTAssertEqual(error as? TaskIDError, TaskIDError.invalidBranchName)
        }
    }

    func testRejectsSpaces() {
        XCTAssertThrowsError(try validator.validate("task name")) { error in
            if case TaskIDError.invalidCharacter(let c) = error {
                XCTAssertEqual(c, " ")
            } else {
                XCTFail("Expected invalidCharacter error")
            }
        }
    }

    func testRejectsSpecialCharacters() {
        XCTAssertThrowsError(try validator.validate("task@name")) { error in
            if case TaskIDError.invalidCharacter(let c) = error {
                XCTAssertEqual(c, "@")
            } else {
                XCTFail("Expected invalidCharacter error")
            }
        }
    }

    func testRejectsUnicodeCharacters() {
        XCTAssertThrowsError(try validator.validate("task名")) { error in
            if case TaskIDError.invalidCharacter = error {
            } else {
                XCTFail("Expected invalidCharacter error, got \(error)")
            }
        }
    }

    func testSanitizedPathReturnsValidPath() throws {
        let container = URL(fileURLWithPath: "/tmp/worktrees")
        let path = try validator.sanitizedPath(for: "task-123", under: container)
        XCTAssertTrue(path.path.hasPrefix(container.path))
        XCTAssertTrue(path.path.hasSuffix("task-123"))
    }

    func testSanitizedPathRejectsTraversal() {
        let container = URL(fileURLWithPath: "/tmp/worktrees")
        XCTAssertThrowsError(try validator.sanitizedPath(for: "../escape", under: container))
    }

    func testSanitizedPathRejectsInvalidID() {
        let container = URL(fileURLWithPath: "/tmp/worktrees")
        XCTAssertThrowsError(try validator.sanitizedPath(for: "", under: container))
    }
}
