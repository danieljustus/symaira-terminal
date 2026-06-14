import Foundation
import Testing
@testable import SymairaUI

@Suite struct BrowserPaneTests {
    @Test @MainActor func instantiationCreatesPaneWithID() {
        let pane = BrowserPane()
        #expect(pane.paneID != UUID())
        #expect(pane.kind == .browser)
    }

    @Test func paneKindTerminalIsNotBrowser() {
        let kind = PaneKind.terminal
        #expect(kind != .browser)
    }

    @Test func paneKindBrowserIsBrowser() {
        let kind = PaneKind.browser
        #expect(kind == .browser)
    }

    @Test @MainActor func browserPaneHasView() {
        let pane = BrowserPane()
        let view = pane.view
        #expect(view != nil)
    }

    @Test @MainActor func closeDoesNotCrash() {
        let pane = BrowserPane()
        pane.close()
    }
}
