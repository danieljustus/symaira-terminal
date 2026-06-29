import ControlKit
import GhosttyBridge
import XCTest
@testable import SymairaTerminal

final class ControlSurfaceIntegrationTests: XCTestCase {

    @MainActor
    func testControlServerSnapshotOverSocket() async throws {
        let socketPath = NSTemporaryDirectory().appending("symaira-test-control-\(UUID().uuidString).sock")
        defer { try? FileManager.default.removeItem(atPath: socketPath) }

        let engine = GhosttyEngine()
        let paneManager = PaneManager(engine: engine)
        let adapter = OrchestrationControlAdapter(paneManager: paneManager)

        let server = ControlServer(socketPath: socketPath)
        try await server.start(provider: adapter)

        let client = ControlClient(socketPath: socketPath)
        let snapshot = try await client.snapshot()

        XCTAssertEqual(snapshot.panes.count, paneManager.panes.count)

        await server.stop()
    }
}
