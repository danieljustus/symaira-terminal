import XCTest
@testable import SymairaTerminal

final class URLSchemeHandlerTests: XCTestCase {

    func testOpenDirectory() {
        let handler = URLSchemeHandler()
        let url = URL(string: "symaira-terminal://open?path=/Users/test/project")!
        guard case .openDirectory(let directory) = handler.parse(url) else {
            XCTFail("Expected openDirectory command")
            return
        }
        XCTAssertEqual(directory.path, "/Users/test/project")
    }

    func testNewTabWithCommand() {
        let handler = URLSchemeHandler()
        let url = URL(string: "symaira-terminal://new-tab?command=npm%20run%20dev")!
        guard case .openTab(let command, let workingDirectory) = handler.parse(url) else {
            XCTFail("Expected openTab command")
            return
        }
        XCTAssertEqual(command, "npm run dev")
        XCTAssertNil(workingDirectory)
    }

    func testNewTabWithoutCommand() {
        let handler = URLSchemeHandler()
        let url = URL(string: "symaira-terminal://new-tab")!
        guard case .openTab(let command, let workingDirectory) = handler.parse(url) else {
            XCTFail("Expected openTab command")
            return
        }
        XCTAssertNil(command)
        XCTAssertNil(workingDirectory)
    }

    func testNewTabWithCommandAndCwd() {
        let handler = URLSchemeHandler()
        let url = URL(string: "symaira-terminal://new-tab?command=npm%20run%20dev&cwd=/Users/test/project")!
        guard case .openTab(let command, let workingDirectory) = handler.parse(url) else {
            XCTFail("Expected openTab command")
            return
        }
        XCTAssertEqual(command, "npm run dev")
        XCTAssertEqual(workingDirectory?.path, "/Users/test/project")
    }

    func testNewTabWithCwdOnly() {
        let handler = URLSchemeHandler()
        let url = URL(string: "symaira-terminal://new-tab?cwd=/Users/test/project")!
        guard case .openTab(let command, let workingDirectory) = handler.parse(url) else {
            XCTFail("Expected openTab command")
            return
        }
        XCTAssertNil(command)
        XCTAssertEqual(workingDirectory?.path, "/Users/test/project")
    }

    func testUnknownSchemeReturnsNil() {
        let handler = URLSchemeHandler()
        let url = URL(string: "https://example.com/open?path=/foo")!
        XCTAssertNil(handler.parse(url))
    }
}
