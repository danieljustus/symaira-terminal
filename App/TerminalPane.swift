import AgentKit
import AppKit
import GhosttyBridge
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
        
        if let terminalView = surface?.view {
            terminalView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(terminalView)
        }
        
        let editorView = inputEditor.view
        editorView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(editorView)
        
        NSLayoutConstraint.activate([
            container.subviews[0].topAnchor.constraint(equalTo: container.topAnchor),
            container.subviews[0].leadingAnchor.constraint(equalTo: container.leadingAnchor),
            container.subviews[0].trailingAnchor.constraint(equalTo: container.trailingAnchor),
            
            editorView.topAnchor.constraint(equalTo: container.subviews[0].bottomAnchor),
            editorView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            editorView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            editorView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            editorView.heightAnchor.constraint(greaterThanOrEqualToConstant: 32),
            editorView.heightAnchor.constraint(lessThanOrEqualToConstant: 200),
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
