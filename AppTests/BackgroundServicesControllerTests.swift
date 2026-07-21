import GhosttyBridge
import XCTest
@testable import SymairaTerminal

/// Tests for the background-services lifecycle controller extracted from AppDelegate.
@MainActor
final class BackgroundServicesControllerTests: XCTestCase {

    func testInitCreatesAdapterAndServers() {
        let engine = GhosttyEngine()
        let paneManager = PaneManager(engine: engine)
        let controller = BackgroundServicesController(paneManager: paneManager)

        // Before start(), server references are nil.
        XCTAssertNil(controller.controlServer)
        XCTAssertNil(controller.mcpServer)
    }

    func testStartSetsServerReferences() {
        let engine = GhosttyEngine()
        let paneManager = PaneManager(engine: engine)
        let controller = BackgroundServicesController(paneManager: paneManager)

        controller.start()

        // After start(), server references should be set (even if the
        // actual bind may fail in CI without a real socket path).
        XCTAssertNotNil(controller.controlServer)
        XCTAssertNotNil(controller.mcpServer)
    }

    func testStopIsIdempotent() async {
        let engine = GhosttyEngine()
        let paneManager = PaneManager(engine: engine)
        let controller = BackgroundServicesController(paneManager: paneManager)

        // stop() without start() should not crash
        await controller.stop()
        await controller.stop() // calling again is safe
    }

    func testStartThenStop() async {
        let engine = GhosttyEngine()
        let paneManager = PaneManager(engine: engine)
        let controller = BackgroundServicesController(paneManager: paneManager)

        controller.start()
        XCTAssertNotNil(controller.controlServer)
        XCTAssertNotNil(controller.mcpServer)

        await controller.stop()
        // stop() sets servers to nil? Actually no — it just calls stop() on them.
        // The servers are still non-nil references. Verify no crash.
    }
}
