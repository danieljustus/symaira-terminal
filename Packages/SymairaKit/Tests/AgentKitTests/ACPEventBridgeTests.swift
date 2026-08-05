import Foundation
import XCTest
@testable import AgentKit

final class ACPEventBridgeTests: XCTestCase {
    private let paneID = UUID()

    func testStatusChangeUpdatesEngine() {
        let bridge = ACPEventBridge()
        bridge.handleEvent(.statusChange(status: "working"), for: paneID)
        let engine = bridge.status(for: paneID)
        XCTAssertEqual(engine.current, .running)
    }

    func testPermissionRequestIsStoredAndSetsAwaitingApproval() {
        let bridge = ACPEventBridge()
        bridge.handleEvent(.permissionRequest(id: 7, toolName: "write_file", description: "write to file"), for: paneID)

        let pending = bridge.pendingPermissionsForPane(paneID)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.toolName, "write_file")
        XCTAssertEqual(pending.first?.paneID, paneID)
        XCTAssertEqual(bridge.status(for: paneID).current, .awaitingApproval)
    }

    func testRespondInvokesHandlerAndReturnsToRunning() {
        let bridge = ACPEventBridge()
        bridge.handleEvent(.permissionRequest(id: 7, toolName: "shell", description: nil), for: paneID)

        var received: Bool?
        bridge.registerResponseHandler(for: 7) { allowed in received = allowed }
        bridge.respond(to: 7, allowed: true)

        XCTAssertEqual(received, true)
        XCTAssertTrue(bridge.pendingPermissionsForPane(paneID).isEmpty)
        XCTAssertEqual(bridge.status(for: paneID).current, .running)
    }

    func testRespondWithoutHandlerStillClearsPending() {
        let bridge = ACPEventBridge()
        bridge.handleEvent(.permissionRequest(id: 3, toolName: "shell", description: nil), for: paneID)
        bridge.respond(to: 3, allowed: false)
        XCTAssertTrue(bridge.pendingPermissionsForPane(paneID).isEmpty)
    }

    func testErrorEventSetsErrorStatus() {
        let bridge = ACPEventBridge()
        bridge.handleEvent(.error(code: -32000, message: "boom"), for: paneID)
        XCTAssertEqual(bridge.status(for: paneID).current, .error)
    }

    func testToolEventsAreIgnored() {
        let bridge = ACPEventBridge()
        bridge.handleEvent(.toolCall(id: "t1", name: "ls", arguments: [:]), for: paneID)
        bridge.handleEvent(.toolResult(id: "t1", result: "out"), for: paneID)
        XCTAssertEqual(bridge.status(for: paneID).current, .idle)
        XCTAssertTrue(bridge.pendingPermissionsForPane(paneID).isEmpty)
    }

    func testPendingPermissionsAreScopedPerPane() {
        let otherPane = UUID()
        let bridge = ACPEventBridge()
        bridge.handleEvent(.permissionRequest(id: 1, toolName: "a", description: nil), for: paneID)
        bridge.handleEvent(.permissionRequest(id: 2, toolName: "b", description: nil), for: otherPane)

        XCTAssertEqual(bridge.pendingPermissionsForPane(paneID).count, 1)
        XCTAssertEqual(bridge.pendingPermissionsForPane(otherPane).count, 1)
    }
}

final class CommitTrailerTests: XCTestCase {
    func testAppendTrailerToMessage() {
        let message = "Fix the thing"
        let result = CommitTrailer.appendTrailer(to: message, transcriptID: "t-123")
        XCTAssertTrue(result.contains("Fix the thing"))
        XCTAssertTrue(result.contains("\n\nSymaira-Transcript: t-123"))
    }

    func testAppendTrailerToEmptyMessage() {
        let result = CommitTrailer.appendTrailer(to: "  \n ", transcriptID: "t-1")
        XCTAssertEqual(result, "Symaira-Transcript: t-1")
    }

    func testExtractTranscriptIDFromMessage() {
        let message = """
        Fix the thing

        Symaira-Transcript: t-456
        """
        XCTAssertEqual(CommitTrailer.extractTranscriptID(from: message), "t-456")
    }

    func testExtractReturnsNilWhenMissing() {
        XCTAssertNil(CommitTrailer.extractTranscriptID(from: "Just a commit"))
    }

    func testExtractReturnsNilForEmptyID() {
        let message = "Fix\n\nSymaira-Transcript:   "
        XCTAssertNil(CommitTrailer.extractTranscriptID(from: message))
    }

    func testRoundTrip() {
        let message = "Do the work"
        let appended = CommitTrailer.appendTrailer(to: message, transcriptID: "t-789")
        XCTAssertEqual(CommitTrailer.extractTranscriptID(from: appended), "t-789")
    }
}

final class GeminiACPAdapterTests: XCTestCase {
    private func makeAdapter() -> GeminiACPAdapter {
        let config = ACPConfiguration(
            executable: URL(fileURLWithPath: "/bin/echo"),
            environment: ["GOOGLE_API_KEY": "dummy-key"]
        )
        return GeminiACPAdapter(client: ACPClient(configuration: config), configuration: config)
    }

    func testNormalizesWriteFileToolName() {
        let adapter = makeAdapter()
        var received: ACPEvent?
        adapter.handleEvent(.permissionRequest(id: 1, toolName: "write_file", description: "w")) { event in
            received = event
        }
        guard case .permissionRequest(let id, let toolName, _) = received else {
            return XCTFail("expected permissionRequest, got \(String(describing: received))")
        }
        XCTAssertEqual(id, 1)
        XCTAssertEqual(toolName, "file-write")
    }

    func testNormalizesShellToolName() {
        let adapter = makeAdapter()
        var received: ACPEvent?
        adapter.handleEvent(.permissionRequest(id: 2, toolName: "run_command", description: nil)) { event in
            received = event
        }
        guard case .permissionRequest(_, let toolName, _) = received else {
            return XCTFail("expected permissionRequest")
        }
        XCTAssertEqual(toolName, "shell")
    }

    func testPassesThroughUnknownToolNames() {
        let adapter = makeAdapter()
        var received: ACPEvent?
        adapter.handleEvent(.permissionRequest(id: 3, toolName: "custom_tool", description: nil)) { event in
            received = event
        }
        guard case .permissionRequest(_, let toolName, _) = received else {
            return XCTFail("expected permissionRequest")
        }
        XCTAssertEqual(toolName, "custom_tool")
    }

    func testPassesThroughNonPermissionEvents() {
        let adapter = makeAdapter()
        var received: ACPEvent?
        adapter.handleEvent(.statusChange(status: "done")) { event in
            received = event
        }
        guard case .statusChange(let status) = received else {
            return XCTFail("expected statusChange, got \(String(describing: received))")
        }
        XCTAssertEqual(status, "done")
    }
}
