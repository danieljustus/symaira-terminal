import Foundation
import Testing
@testable import SymairaUI

@Suite struct WorkflowCanvasViewTests {
    @Test @MainActor func missingResourceHTMLContainsErrorMessage() {
        let view = WorkflowCanvasView()
        let html = view.missingResourceHTML()
        #expect(html.contains("Workflow Canvas unavailable"))
        #expect(html.contains("The Workflow Canvas resource bundle is missing."))
    }
}
