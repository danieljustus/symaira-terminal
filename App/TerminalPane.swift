import AgentKit
import AppKit
import GhosttyBridge
import SwiftUI
import SymairaUI
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
    var view: NSView { containerView }
    private let emptyView = NSView()
    nonisolated(unsafe) let scrollbackBuffer: ScrollbackBuffer
    let configuration: TerminalSurfaceConfiguration
    nonisolated(unsafe) var statusEngine = AgentStatusEngine()
    private(set) var agentStatus: AgentStatus = .idle
    var onStatusChanged: ((AgentStatus) -> Void)?
    var outputTap: (@Sendable ([UInt8]) -> Void)? {
        get { surface?.outputTap }
        set { surface?.outputTap = newValue }
    }

    public var pid: pid_t { surface?.pid ?? -1 }

    private(set) lazy var inputEditor: CommandInputEditor = {
        CommandInputEditor(surface: surface)
    }()

    private lazy var containerView: NSView = {
        let container = NSView()

        // TerminalSurface no longer exposes a view (TerminalCore is AppKit-free).
        // The concrete GhosttySurfaceController in GhosttyBridge owns the NSView;
        // downcast to access it.
        if let ghosttySurface = surface as? GhosttySurfaceController {
            let terminalView = ghosttySurface.view
            terminalView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(terminalView)
        }

        let inputBar = NSHostingView(rootView: CommandInputBar(editor: inputEditor))
        inputBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(inputBar)

        NSLayoutConstraint.activate([
            container.subviews[0].topAnchor.constraint(equalTo: container.topAnchor),
            container.subviews[0].leadingAnchor.constraint(equalTo: container.leadingAnchor),
            container.subviews[0].trailingAnchor.constraint(equalTo: container.trailingAnchor),

            inputBar.topAnchor.constraint(equalTo: container.subviews[0].bottomAnchor),
            inputBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            inputBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            inputBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            inputBar.heightAnchor.constraint(greaterThanOrEqualToConstant: 32),
            inputBar.heightAnchor.constraint(lessThanOrEqualToConstant: 200)
        ])

        return container
    }()

    init(surface: (any TerminalSurface)?, configuration: TerminalSurfaceConfiguration = .init()) {
        self.surface = surface
        self.configuration = configuration
        self.scrollbackBuffer = ScrollbackBuffer(maxLines: configuration.scrollbackLines)
    }

    func updateStatus(_ status: AgentStatus) {
        agentStatus = status
        onStatusChanged?(status)
    }

    func setAlternateScreenActive(_ active: Bool) {
        inputEditor.setAlternateScreenActive(active)
    }

    func close() {
        surface?.close()
        surface = nil
    }
}
