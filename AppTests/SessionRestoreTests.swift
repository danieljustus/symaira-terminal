import AppKit
import GhosttyBridge
import TerminalCore
import XCTest
@testable import SymairaTerminal

/// Regression coverage for the v0.8.1 "dead window" bug: a persisted session
/// with zero panes restored into an empty, input-swallowing window.
final class SessionRestoreTests: XCTestCase {

    @MainActor
    private func makeManager() -> (PaneManager, NSWindow, NSView) {
        let engine = GhosttyEngine()
        let manager = PaneManager(engine: engine)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        let host = NSView(frame: window.contentLayoutRect)
        window.contentView = host
        manager.attach(to: host)
        return (manager, window, host)
    }

    @MainActor
    func testRestoringPanelessSessionStillCreatesAPane() {
        let (manager, window, _) = makeManager()
        let emptyState = SessionState(
            panes: [],
            layout: .pane(index: 0),
            windowFrame: CodableRect(x: 0, y: 0, width: 960, height: 600)
        )

        manager.restoreFromLayout(emptyState, window: window, manager: manager)

        XCTAssertEqual(manager.panes.count, 1, "A paneless session must restore to one live pane, never zero")
        XCTAssertNotNil(manager.currentPane, "The restored pane must become current so it can take focus")
    }

    @MainActor
    func testRestoringNormalSessionPreservesPaneCount() {
        let (manager, window, _) = makeManager()
        let state = SessionState(
            panes: [PaneState(), PaneState()],
            layout: .split(orientation: .vertical, ratio: 0.5, left: .pane(index: 0), right: .pane(index: 1)),
            windowFrame: CodableRect(x: 0, y: 0, width: 960, height: 600)
        )

        manager.restoreFromLayout(state, window: window, manager: manager)

        XCTAssertEqual(manager.panes.count, 2, "A normal session must restore exactly its persisted panes")
    }
}
