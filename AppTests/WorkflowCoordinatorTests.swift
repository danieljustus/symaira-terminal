import AppKit
import XCTest
@testable import SymairaTerminal

@MainActor
final class WorkflowCoordinatorTests: XCTestCase {
    func testShowWorkflowCanvasOpensAWindow() {
        let coordinator = WorkflowCoordinator(paneManager: nil, sidebarViewModel: nil)

        coordinator.showWorkflowCanvas()

        let canvasWindows = NSApp.windows.filter { $0.title == "Workflow Canvas" }
        XCTAssertEqual(canvasWindows.count, 1, "Workflow Canvas should open exactly one window")
        XCTAssertTrue(canvasWindows.first?.isVisible == true, "Workflow Canvas window should be visible")

        canvasWindows.forEach { $0.close() }
    }

    func testShowWorkflowCanvasReusesTheExistingWindow() {
        let coordinator = WorkflowCoordinator(paneManager: nil, sidebarViewModel: nil)

        coordinator.showWorkflowCanvas()
        coordinator.showWorkflowCanvas()

        let canvasWindows = NSApp.windows.filter { $0.title == "Workflow Canvas" }
        XCTAssertEqual(canvasWindows.count, 1, "Repeated invocations must not stack windows")

        canvasWindows.forEach { $0.close() }
    }

    /// The canvas is loaded with `subdirectory: "WorkflowCanvas"`, so the
    /// resource has to survive the build as a folder rather than being
    /// flattened into Resources/. When it is flattened this lookup returns nil
    /// and the canvas silently renders its "unavailable" placeholder instead.
    func testWorkflowCanvasHTMLResolvesInTheAppBundle() {
        let url = Bundle.main.url(
            forResource: "index",
            withExtension: "html",
            subdirectory: "WorkflowCanvas"
        )
        XCTAssertNotNil(url, "Resources/WorkflowCanvas/index.html is missing from the app bundle")
    }

    /// Every menu item built with an explicit target must have an action that
    /// target actually implements — otherwise the item still looks enabled and
    /// silently does nothing when clicked.
    func testEveryMenuItemActionIsImplementedByItsTarget() {
        let delegate = AppDelegate()
        let mainMenu = AppMenuBuilder.buildMainMenu(target: delegate)

        var unimplemented: [String] = []
        for topLevel in mainMenu.items {
            for item in topLevel.submenu?.items ?? [] {
                guard let action = item.action, let target = item.target else { continue }
                if !target.responds(to: action) {
                    unimplemented.append("\(item.title) -> \(NSStringFromSelector(action))")
                }
            }
        }

        XCTAssertEqual(unimplemented, [], "Menu items wired to a selector their target does not implement")
    }
}
