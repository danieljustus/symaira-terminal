import XCTest
import GhosttyBridge
@testable import SymairaTerminal

/// Tests for the URL-scheme dispatch logic extracted from AppDelegate.
@MainActor
final class URLSchemeCoordinatorTests: XCTestCase {

    func testDispatchOpenDirectoryURL() {
        let coordinator = URLSchemeCoordinator()
        let engine = GhosttyEngine()
        let paneManager = PaneManager(engine: engine)
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("url-coord-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let url = URL(string: "symaira-terminal://open?path=\(tmpDir.path)")!
        let countBefore = paneManager.panes.count

        coordinator.dispatch(urls: [url], paneManager: paneManager)

        XCTAssertGreaterThan(paneManager.panes.count, countBefore,
                             "open dispatch should create a new pane")
    }

    func testDispatchNewTabWithCommand() {
        let coordinator = URLSchemeCoordinator()
        let engine = GhosttyEngine()
        let paneManager = PaneManager(engine: engine)
        let url = URL(string: "symaira-terminal://new-tab?command=echo%20hello")!
        let countBefore = paneManager.panes.count

        coordinator.dispatch(urls: [url], paneManager: paneManager)

        XCTAssertGreaterThanOrEqual(paneManager.panes.count, countBefore,
                                    "new-tab dispatch should not reduce pane count")
    }

    func testDispatchUnknownURLIsSkipped() {
        let coordinator = URLSchemeCoordinator()
        let engine = GhosttyEngine()
        let paneManager = PaneManager(engine: engine)
        let url = URL(string: "https://example.com/path")!
        let countBefore = paneManager.panes.count

        coordinator.dispatch(urls: [url], paneManager: paneManager)

        XCTAssertEqual(paneManager.panes.count, countBefore,
                       "Unknown URL scheme should be silently ignored")
    }

    func testDispatchMultipleURLs() {
        let coordinator = URLSchemeCoordinator()
        let engine = GhosttyEngine()
        let paneManager = PaneManager(engine: engine)
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("url-coord-multi-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let openURL = URL(string: "symaira-terminal://open?path=\(tmpDir.path)")!
        let unknownURL = URL(string: "https://example.com")!
        let countBefore = paneManager.panes.count

        coordinator.dispatch(urls: [openURL, unknownURL], paneManager: paneManager)

        XCTAssertEqual(paneManager.panes.count, countBefore + 1,
                       "Only valid URLs should create panes")
    }

    func testDispatchNewTabWithCwdOnly() {
        let coordinator = URLSchemeCoordinator()
        let engine = GhosttyEngine()
        let paneManager = PaneManager(engine: engine)
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("url-coord-cwd-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let url = URL(string: "symaira-terminal://new-tab?cwd=\(tmpDir.path)")!
        let countBefore = paneManager.panes.count

        coordinator.dispatch(urls: [url], paneManager: paneManager)

        XCTAssertGreaterThan(paneManager.panes.count, countBefore,
                             "new-tab with cwd should create a pane in that directory")
    }

    func testDispatchEmptyURLList() {
        let coordinator = URLSchemeCoordinator()
        let engine = GhosttyEngine()
        let paneManager = PaneManager(engine: engine)
        let countBefore = paneManager.panes.count

        coordinator.dispatch(urls: [], paneManager: paneManager)

        XCTAssertEqual(paneManager.panes.count, countBefore,
                       "Empty URL list should not create any panes")
    }
}
