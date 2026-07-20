import AppKit
import GhosttyBridge
import XCTest
@testable import SymairaTerminal

/// Verifies that `PaneManager.openTab`'s confirmation dialog reflects the
/// actual request origin instead of always claiming an AI agent asked —
/// the same code path is reachable from an MCP tool call and from an
/// arbitrary `symaira-terminal://new-tab` link.
final class PaneManagerOpenTabOriginTests: XCTestCase {

    @MainActor
    func testMCPOriginShowsAIAgentDialog() async throws {
        let engine = GhosttyEngine()
        let paneManager = PaneManager(engine: engine)
        var capturedAlert: NSAlert?
        paneManager.alertRunner = { alert in
            capturedAlert = alert
            return .alertSecondButtonReturn
        }

        _ = await paneManager.openTab(command: "echo hi", workingDirectory: nil, origin: .mcp)

        XCTAssertEqual(capturedAlert?.messageText, "AI Request: Open New Tab")
        XCTAssertTrue(capturedAlert?.informativeText.contains("An AI agent is requesting") ?? false)
    }

    @MainActor
    func testURLSchemeOriginShowsExternalLinkDialog() async throws {
        let engine = GhosttyEngine()
        let paneManager = PaneManager(engine: engine)
        var capturedAlert: NSAlert?
        paneManager.alertRunner = { alert in
            capturedAlert = alert
            return .alertSecondButtonReturn
        }

        _ = await paneManager.openTab(command: "echo hi", workingDirectory: nil, origin: .urlScheme)

        XCTAssertEqual(capturedAlert?.messageText, "External Link: Open New Tab")
        XCTAssertTrue(capturedAlert?.informativeText.contains("not an AI agent") ?? false)
    }

    @MainActor
    func testURLSchemeParsedCommandRoutesWithURLSchemeOrigin() async throws {
        // The exact command/workingDirectory URLSchemeHandler extracts from a
        // symaira-terminal://new-tab link is what AppDelegate forwards to
        // openTab(origin: .urlScheme) — confirm that pairing end to end.
        let handler = URLSchemeHandler()
        let url = URL(string: "symaira-terminal://new-tab?command=echo%20hi")!
        guard case .openTab(let command, let workingDirectory) = handler.parse(url), let command else {
            XCTFail("Expected openTab command with a non-nil command string")
            return
        }

        let engine = GhosttyEngine()
        let paneManager = PaneManager(engine: engine)
        var capturedAlert: NSAlert?
        paneManager.alertRunner = { alert in
            capturedAlert = alert
            return .alertSecondButtonReturn
        }

        _ = await paneManager.openTab(command: command, workingDirectory: workingDirectory, origin: .urlScheme)

        XCTAssertEqual(capturedAlert?.messageText, "External Link: Open New Tab")
    }
}
