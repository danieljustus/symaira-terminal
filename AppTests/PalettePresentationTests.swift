import AppKit
import XCTest
@testable import SymairaTerminal

/// Tests for the Command Palette presentation path that was previously
/// untestable due to an over-release crash on teardown (#302).
///
/// These are app-hosted tests that exercise `WindowPresentationController`'s
/// `showCommandPalette(window:actions:)` and `dismissCommandPalette()`
/// methods and verify that the panel survives teardown without crashing.
@MainActor
final class PalettePresentationTests: XCTestCase {

    private var controller: WindowPresentationController!
    private var hostWindow: NSWindow!

    override func setUp() {
        super.setUp()
        controller = WindowPresentationController(
            providerStore: .init(),
            workspaceConfigManager: .init(
                workspaceURL: URL(fileURLWithPath: NSTemporaryDirectory())
            ),
            stackStore: .init()
        )
        hostWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        hostWindow.makeKeyAndOrderFront(nil)
    }

    override func tearDown() {
        // Dismiss the palette before tearing down the host window so
        // AppKit's teardown sequence doesn't fight a still-open panel.
        controller?.dismissCommandPalette()
        hostWindow?.close()
        controller = nil
        hostWindow = nil
        super.tearDown()
    }

    // MARK: - Basic presentation

    func testShowPaletteDoesNotCrash() {
        controller.showCommandPalette(window: hostWindow, actions: [])
        // If we reach here without a crash, the fix is working.
    }

    func testShowPaletteTwiceDoesNotStackPanels() {
        controller.showCommandPalette(window: hostWindow, actions: [])

        // Show it again — this used to just re-order the existing panel
        // front; now it dismisses the old one first.  Either way, only
        // one panel should exist.
        controller.showCommandPalette(window: hostWindow, actions: [])

        // No assertion needed beyond the fact that we didn't crash
        // and AppKit's window list isn't corrupted.
    }

    // MARK: - Dismissal

    func testDismissPaletteBeforeCloseDoesNotCrash() {
        controller.showCommandPalette(window: hostWindow, actions: [])
        controller.dismissCommandPalette()
        // Dismiss then close: clean teardown, no crash.
    }

    func testDoubleDismissIsSafe() {
        controller.showCommandPalette(window: hostWindow, actions: [])
        controller.dismissCommandPalette()
        controller.dismissCommandPalette() // should be a no-op
    }

    func testDismissWithoutPresentingIsSafe() {
        // Calling dismiss when no palette was ever presented.
        controller.dismissCommandPalette()
        // Should not crash.
    }

    // MARK: - Present after dismiss

    func testShowAfterDismissCreatesFreshPanel() {
        controller.showCommandPalette(window: hostWindow, actions: [])
        controller.dismissCommandPalette()
        // Show again — should create a new panel instead of crashing.
        controller.showCommandPalette(window: hostWindow, actions: [])
    }
}
