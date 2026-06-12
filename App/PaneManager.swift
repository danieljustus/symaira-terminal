import AppKit
import GhosttyBridge
import TerminalCore

@MainActor
final class PaneManager {
    private(set) var panes: [TerminalPane] = []
    private(set) var currentPane: TerminalPane?
    private var splitViews: [UUID: NSSplitView] = [:]

    let engine: GhosttyEngine
    private weak var hostView: NSView?
    private var oscParsers: [UUID: OSCStreamParser] = [:]

    var onPaneChanged: ((TerminalPane?) -> Void)?
    var onPanesChanged: (([TerminalPane]) -> Void)?
    var onOSCTap: ((UUID, OSCEvent) -> Void)?

    init(engine: GhosttyEngine) {
        self.engine = engine
    }

    func attach(to view: NSView) {
        self.hostView = view
    }

    func createPane(at configuration: TerminalSurfaceConfiguration = .init()) -> TerminalPane {
        let surface: (any TerminalSurface)?
        do {
            surface = try engine.makeSurface(configuration: configuration)
        } catch {
            NSLog("symaira: failed to create terminal surface: %@", String(describing: error))
            surface = nil
        }
        let pane = TerminalPane(surface: surface, configuration: configuration)
        panes.append(pane)
        oscParsers[pane.paneID] = OSCStreamParser()

        surface?.outputTap = { [weak self, weak pane] bytes in
            guard let self, let pane else { return }
            pane.scrollbackBuffer.append(bytes)
            Task { @MainActor in
                guard var parser = self.oscParsers[pane.paneID] else { return }
                for event in parser.feed(bytes) {
                    self.onOSCTap?(pane.paneID, event)
                }
                self.oscParsers[pane.paneID] = parser
            }
        }

        currentPane = pane
        onPanesChanged?(panes)
        onPaneChanged?(pane)
        rebuildLayout()
        return pane
    }

    func closePane(_ pane: TerminalPane) {
        guard panes.count > 1, let idx = panes.firstIndex(where: { $0 === pane }) else {
            if panes.count == 1 { pane.close() }
            panes.removeAll()
            currentPane = nil
            onPanesChanged?(panes)
            onPaneChanged?(nil)
            return
        }
        pane.close()
        panes.remove(at: idx)
        oscParsers.removeValue(forKey: pane.paneID)
        if currentPane === pane {
            currentPane = panes[min(idx, panes.count - 1)]
        }
        onPanesChanged?(panes)
        onPaneChanged?(currentPane)
        rebuildLayout()
    }

    func focusNext() {
        guard let cur = currentPane, let idx = panes.firstIndex(where: { $0 === cur }) else { return }
        let next = panes[(idx + 1) % panes.count]
        currentPane = next
        onPaneChanged?(next)
        next.view.window?.makeFirstResponder(next.view)
    }

    func focusPrevious() {
        guard let cur = currentPane, let idx = panes.firstIndex(where: { $0 === cur }) else { return }
        let prev = panes[(idx - 1 + panes.count) % panes.count]
        currentPane = prev
        onPaneChanged?(prev)
        prev.view.window?.makeFirstResponder(prev.view)
    }

    func selectPane(at index: Int) {
        guard index >= 0, index < panes.count else { return }
        let pane = panes[index]
        currentPane = pane
        onPaneChanged?(pane)
        pane.view.window?.makeFirstResponder(pane.view)
    }

    func focusNextActive() {
        guard let cur = currentPane, let idx = panes.firstIndex(where: { $0 === cur }) else { return }
        let activePanes = panes.enumerated().filter { $0.element.agentStatus != .idle && $0.element.agentStatus != .done }
        guard !activePanes.isEmpty else { return }

        if let nextActive = activePanes.first(where: { $0.offset > idx }) {
            selectPane(at: nextActive.offset)
        } else if let firstActive = activePanes.first {
            selectPane(at: firstActive.offset)
        }
    }

    func focusPreviousActive() {
        guard let cur = currentPane, let idx = panes.firstIndex(where: { $0 === cur }) else { return }
        let activePanes = panes.enumerated().filter { $0.element.agentStatus != .idle && $0.element.agentStatus != .done }
        guard !activePanes.isEmpty else { return }

        if let prevActive = activePanes.last(where: { $0.offset < idx }) {
            selectPane(at: prevActive.offset)
        } else if let lastActive = activePanes.last {
            selectPane(at: lastActive.offset)
        }
    }

    func focusLongestBlocked() {
        let blocked = panes.filter { pane in
            pane.agentStatus == .awaitingApproval || pane.agentStatus == .error
        }
        if let target = blocked.first, let idx = panes.firstIndex(where: { $0 === target }) {
            selectPane(at: idx)
        } else {
            focusNext()
        }
    }

    func splitHorizontal() {
        split(orientation: .horizontal)
    }

    func splitVertical() {
        split(orientation: .vertical)
    }

    private func split(orientation: SplitOrientation) {
        guard let cur = currentPane else { return }
        let newPane = createPane()
        guard let hostView else { return }

        if let existingSplit = findSplitView(for: cur) {
            let newSplit = NSSplitView()
            newSplit.isVertical = orientation == .vertical
            newSplit.dividerStyle = .thin
            newSplit.autosaveName = nil

            if let parentIdx = existingSplit.subviews.firstIndex(where: { $0 === cur.view }) {
                existingSplit.insertArrangedSubview(newSplit, at: parentIdx + 1)
                cur.view.translatesAutoresizingMaskIntoConstraints = true
                newPane.view.translatesAutoresizingMaskIntoConstraints = true
                newSplit.addArrangedSubview(cur.view)
                newSplit.addArrangedSubview(newPane.view)
            }
        } else {
            let splitView = NSSplitView()
            splitView.isVertical = orientation == .vertical
            splitView.dividerStyle = .thin
            splitView.translatesAutoresizingMaskIntoConstraints = false

            hostView.subviews.forEach { $0.removeFromSuperview() }
            hostView.addSubview(splitView)

            NSLayoutConstraint.activate([
                splitView.topAnchor.constraint(equalTo: hostView.topAnchor),
                splitView.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
                splitView.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
                splitView.bottomAnchor.constraint(equalTo: hostView.bottomAnchor),
            ])

            cur.view.translatesAutoresizingMaskIntoConstraints = true
            newPane.view.translatesAutoresizingMaskIntoConstraints = true
            splitView.addArrangedSubview(cur.view)
            splitView.addArrangedSubview(newPane.view)
            splitViews[UUID()] = splitView
        }
        currentPane = newPane
        onPaneChanged?(newPane)
        onPanesChanged?(panes)
    }

    private func findSplitView(for pane: TerminalPane) -> NSSplitView? {
        for (_, splitView) in splitViews {
            if splitView.subviews.contains(where: { $0 === pane.view }) {
                return splitView
            }
        }
        return nil
    }

    func rebuildLayout() {
        guard let hostView else { return }
        hostView.subviews.forEach { $0.removeFromSuperview() }
        splitViews.removeAll()

        if panes.count == 1, let pane = panes.first {
            let view = pane.view
            view.translatesAutoresizingMaskIntoConstraints = false
            hostView.addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: hostView.topAnchor),
                view.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
                view.bottomAnchor.constraint(equalTo: hostView.bottomAnchor),
            ])
            return
        }

        guard panes.count >= 2 else { return }
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false

        for pane in panes {
            // NSSplitView manages arranged subviews by frame.
            pane.view.translatesAutoresizingMaskIntoConstraints = true
            splitView.addArrangedSubview(pane.view)
        }

        hostView.addSubview(splitView)
        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: hostView.topAnchor),
            splitView.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: hostView.bottomAnchor),
        ])
        splitViews[UUID()] = splitView
    }

    var stateForPersistence: SessionState {
        let paneStates = panes.map { pane -> PaneState in
            PaneState(
                executablePath: "/bin/zsh",
                arguments: ["-l"],
                workingDirectory: pane.configuration.workingDirectory?.path,
                columns: 80,
                rows: 24
            )
        }
        var layout: SplitNode = .pane(index: 0)
        if panes.count > 1 {
            layout = .split(orientation: .horizontal, ratio: 0.5,
                           left: .pane(index: 0),
                           right: .split(orientation: .horizontal, ratio: 0.5,
                                        left: .pane(index: 1),
                                        right: panes.count > 2 ? .pane(index: 2) : .pane(index: 1)))
        }
        return SessionState(panes: paneStates, layout: layout)
    }
}
