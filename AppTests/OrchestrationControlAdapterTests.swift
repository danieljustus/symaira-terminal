import AppKit
import XCTest
@testable import SymairaTerminal

final class OrchestrationControlAdapterTests: XCTestCase {

    @MainActor
    func testRequestOpenTabDenyCreatesNoPane() async throws {
        let engine = GhosttyEngine()
        let paneManager = PaneManager(engine: engine)
        paneManager.alertRunner = { _ in .alertSecondButtonReturn }

        let adapter = OrchestrationControlAdapter(paneManager: paneManager)
        let result = try await adapter.requestOpenTab(command: "echo denied")

        XCTAssertEqual(result.status, "denied")
        XCTAssertTrue(paneManager.panes.isEmpty, "Denying the prompt must not create a pane")
    }
}
