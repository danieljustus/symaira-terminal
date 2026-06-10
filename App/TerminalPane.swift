import AppKit
import GhosttyBridge
import TerminalCore

@MainActor
protocol PaneContainer: AnyObject {
    var paneID: UUID { get }
    var surface: (any TerminalSurface)? { get }
    var view: NSView { get }
    func close()
}

@MainActor
final class TerminalPane: PaneContainer {
    let paneID = UUID()
    private(set) var surface: (any TerminalSurface)?
    var view: NSView { surface?.view ?? emptyView }
    private let emptyView = NSView()
    var outputTap: (@Sendable ([UInt8]) -> Void)? {
        get { surface?.outputTap }
        set { surface?.outputTap = newValue }
    }

    init(surface: (any TerminalSurface)?) {
        self.surface = surface
    }

    func close() {
        surface?.close()
        surface = nil
    }
}
