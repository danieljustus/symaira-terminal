import AppKit
import GhosttyBridge
import SymairaUI
import TerminalCore
import WorktreeKit

@MainActor
final class PaneManager {
    private(set) var panes: [TerminalPane] = []
    private(set) var browserPanes: [BrowserPane] = []
    private(set) var currentPane: TerminalPane?
    private(set) var zoomedPane: TerminalPane?
    private var splitViews: [UUID: NSSplitView] = [:]
    private var currentLayout: SplitNode = .pane(index: 0)

    let engine: GhosttyEngine
    private weak var hostView: NSView?
    private var oscParsers: [UUID: OSCStreamParser] = [:]
    var worktreeManager: WorktreeManager?

    /// Test hook: override to control NSAlert responses without displaying UI.
    var alertRunner: ((NSAlert) -> NSApplication.ModalResponse)?

    var onPaneChanged: ((TerminalPane?) -> Void)?
    var onPanesChanged: (([TerminalPane]) -> Void)?
    var onOSCTap: ((UUID, OSCEvent) -> Void)?

    init(engine: GhosttyEngine, repositoryURL: URL? = nil) {
        self.engine = engine
        if let repoURL = repositoryURL {
            self.worktreeManager = WorktreeManager(repositoryURL: repoURL)
        }
    }

    private func defaultConfiguration() -> TerminalSurfaceConfiguration {
        let shell = UserDefaults.standard.string(forKey: "defaultShell") ?? "/bin/zsh"
        let scrollbackLines = UserDefaults.standard.integer(forKey: "scrollbackLines")
        let effectiveScrollback = scrollbackLines > 0 ? scrollbackLines : 10_000
        var config = TerminalSurfaceConfiguration(
            executablePath: shell,
            arguments: ["-l"],
            scrollbackLines: effectiveScrollback
        )
        // Start new panes in the user's home directory. Without an explicit cwd
        // the PTY inherits the app process's launch directory (e.g. the build
        // folder), which both opens shells in the wrong place and leaks that
        // directory name into the tab/window title via the shell's OSC title.
        config.workingDirectory = URL(fileURLWithPath: NSHomeDirectory())
        return config
    }

    func attach(to view: NSView) {
        self.hostView = view
    }

    func createPane(at configuration: TerminalSurfaceConfiguration? = nil) -> TerminalPane {
        let config = configuration ?? defaultConfiguration()
        let surface: (any TerminalSurface)?
        do {
            surface = try engine.makeSurface(configuration: config)
        } catch {
            NSLog("symaira: failed to create terminal surface: %@", String(describing: error))
            surface = nil
        }
        let pane = TerminalPane(surface: surface, configuration: config)
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

    func createPane(inDirectory directory: URL) -> TerminalPane {
        var config = defaultConfiguration()
        config.workingDirectory = directory
        return createPane(at: config)
    }

    @discardableResult
    func createBrowserPane(url: URL? = nil) -> BrowserPane {
        let browserPane = BrowserPane()
        browserPanes.append(browserPane)

        if let initialURL = url {
            browserPane.navigate(to: initialURL.absoluteString)
        }

        guard let currentPane, let hostView else {
            onPanesChanged?(panes)
            return browserPane
        }

        let currentView = currentPane.view
        let browserView = browserPane.view

        if let existingSplit = findSplitView(for: currentPane) {
            let newSplit = NSSplitView()
            newSplit.isVertical = true
            newSplit.dividerStyle = .thin
            newSplit.autosaveName = nil

            if let parentIdx = existingSplit.subviews.firstIndex(where: { $0 === currentView }) {
                existingSplit.insertArrangedSubview(newSplit, at: parentIdx + 1)
                currentView.translatesAutoresizingMaskIntoConstraints = true
                browserView.translatesAutoresizingMaskIntoConstraints = true
                newSplit.addArrangedSubview(currentView)
                newSplit.addArrangedSubview(browserView)
            }
        } else {
            let splitView = NSSplitView()
            splitView.isVertical = true
            splitView.dividerStyle = .thin
            splitView.translatesAutoresizingMaskIntoConstraints = false

            hostView.subviews.forEach { $0.removeFromSuperview() }
            hostView.addSubview(splitView)

            NSLayoutConstraint.activate([
                splitView.topAnchor.constraint(equalTo: hostView.topAnchor),
                splitView.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
                splitView.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
                splitView.bottomAnchor.constraint(equalTo: hostView.bottomAnchor)
            ])

            currentView.translatesAutoresizingMaskIntoConstraints = true
            browserView.translatesAutoresizingMaskIntoConstraints = true
            splitView.addArrangedSubview(currentView)
            splitView.addArrangedSubview(browserView)
            splitViews[UUID()] = splitView
        }

        return browserPane
    }

    func closeBrowserPane(_ browserPane: BrowserPane) {
        guard let idx = browserPanes.firstIndex(where: { $0 === browserPane }) else { return }
        browserPane.close()
        browserPanes.remove(at: idx)
        rebuildLayout()
    }

    func forkSession(from sourcePane: TerminalPane) -> TerminalPane? {
        guard let worktreeManager else {
            NSLog("symaira: cannot fork session - no worktree manager configured")
            return nil
        }

        let sourceConfig = sourcePane.configuration
        guard let sourceCWD = sourceConfig.workingDirectory else {
            NSLog("symaira: cannot fork session - source pane has no working directory")
            return nil
        }

        let taskID = "fork-\(UUID().uuidString.prefix(8))"
        let newWorktree: Worktree
        do {
            newWorktree = try worktreeManager.create(taskID: taskID, baseRef: "HEAD")
        } catch {
            NSLog("symaira: failed to create worktree for fork: %@", String(describing: error))
            return nil
        }

        var newConfig = defaultConfiguration()
        newConfig.workingDirectory = newWorktree.path
        newConfig.environment = EnvironmentSanitizer.sanitizedProcessEnvironment()

        let newPane = createPane(at: newConfig)
        return newPane
    }

    func closePane(_ pane: TerminalPane) {
        if zoomedPane === pane {
            zoomedPane = nil
        }
        guard panes.count > 1, let idx = panes.firstIndex(where: { $0 === pane }) else {
            if panes.count == 1 { pane.close() }
            panes.removeAll()
            currentPane = nil
            currentLayout = .pane(index: 0)
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
        currentLayout = rebuildLayoutTree()
        onPanesChanged?(panes)
        onPaneChanged?(currentPane)
        rebuildLayout()
    }

    func focusNext() {
        guard let cur = currentPane, let idx = panes.firstIndex(where: { $0 === cur }) else { return }
        let next = panes[(idx + 1) % panes.count]
        currentPane = next
        onPaneChanged?(next)
        focusSurface(of: next)
    }

    func focusPrevious() {
        guard let cur = currentPane, let idx = panes.firstIndex(where: { $0 === cur }) else { return }
        let prev = panes[(idx - 1 + panes.count) % panes.count]
        currentPane = prev
        onPaneChanged?(prev)
        focusSurface(of: prev)
    }

    func selectPane(at index: Int) {
        guard index >= 0, index < panes.count else { return }
        let pane = panes[index]
        currentPane = pane
        onPaneChanged?(pane)
        focusSurface(of: pane)
    }

    /// Make the libghostty surface the first responder so keystrokes reach the
    /// PTY. Focusing the wrapper `pane.view` (a plain container NSView) does not
    /// forward key events to the Metal surface, so the terminal would silently
    /// swallow input. Falls back to the container only if the surface is absent.
    private func focusSurface(of pane: TerminalPane) {
        let target = pane.surface?.view ?? pane.view
        target.window?.makeFirstResponder(target)
    }

    /// Focus the current pane's surface. Call this once the hosting window is on
    /// screen — at `createPane` time during launch the view is not yet in a
    /// window, so the initial pane would otherwise never become first responder.
    func focusCurrent() {
        guard let pane = currentPane else { return }
        focusSurface(of: pane)
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

    // MARK: - Directional Navigation

    enum FocusDirection {
        case left, right, up, down
    }

    func focus(in direction: FocusDirection) {
        guard let currentPane = currentPane, panes.count > 1 else { return }

        let currentFrame = currentPane.view.convert(currentPane.view.bounds, to: nil)
        let currentCenter = NSPoint(x: currentFrame.midX, y: currentFrame.midY)

        var bestCandidate: TerminalPane?
        var minDistance = Double.infinity

        for pane in panes {
            if pane === currentPane { continue }
            let candidateFrame = pane.view.convert(pane.view.bounds, to: nil)
            let candidateCenter = NSPoint(x: candidateFrame.midX, y: candidateFrame.midY)

            let dx = candidateCenter.x - currentCenter.x
            let dy = candidateCenter.y - currentCenter.y

            var isCandidate = false
            var primaryDelta: Double = 0
            var secondaryDelta: Double = 0

            switch direction {
            case .left:
                if dx < -1 {
                    isCandidate = true
                    primaryDelta = -dx
                    secondaryDelta = dy
                }
            case .right:
                if dx > 1 {
                    isCandidate = true
                    primaryDelta = dx
                    secondaryDelta = dy
                }
            case .up:
                if dy > 1 { // In macOS, Y increases upwards
                    isCandidate = true
                    primaryDelta = dy
                    secondaryDelta = dx
                }
            case .down:
                if dy < -1 {
                    isCandidate = true
                    primaryDelta = -dy
                    secondaryDelta = dx
                }
            }

            if isCandidate {
                // Calculate distance with a penalty for misalignment on the secondary axis
                let dist = primaryDelta + 4.0 * abs(secondaryDelta)
                if dist < minDistance {
                    minDistance = dist
                    bestCandidate = pane
                }
            }
        }

        if let target = bestCandidate, let idx = panes.firstIndex(where: { $0 === target }) {
            selectPane(at: idx)
        }
    }

    // MARK: - Zoom (Maximize / Restore)

    func toggleZoom() {
        if zoomedPane != nil {
            zoomedPane = nil
        } else if let cur = currentPane {
            zoomedPane = cur
        }
        rebuildLayout()
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
                splitView.bottomAnchor.constraint(equalTo: hostView.bottomAnchor)
            ])

            cur.view.translatesAutoresizingMaskIntoConstraints = true
            newPane.view.translatesAutoresizingMaskIntoConstraints = true
            splitView.addArrangedSubview(cur.view)
            splitView.addArrangedSubview(newPane.view)
            splitViews[UUID()] = splitView
        }

        if let curIdx = panes.firstIndex(where: { $0 === cur }) {
            let newIdx = panes.count - 1
            let splitNode: SplitNode = .split(
                orientation: orientation,
                ratio: 0.5,
                left: .pane(index: curIdx),
                right: .pane(index: newIdx)
            )
            currentLayout = replacePane(at: curIdx, with: splitNode, in: currentLayout)
        }

        currentPane = newPane
        onPaneChanged?(newPane)
        onPanesChanged?(panes)
    }

    private func findSplitView(for pane: TerminalPane) -> NSSplitView? {
        for (_, splitView) in splitViews where splitView.subviews.contains(where: { $0 === pane.view }) {
            return splitView
        }
        return nil
    }

    func rebuildLayout() {
        guard let hostView else { return }
        hostView.subviews.forEach { $0.removeFromSuperview() }
        splitViews.removeAll()

        if let zoomed = zoomedPane, panes.contains(where: { $0 === zoomed }) {
            let view = zoomed.view
            view.translatesAutoresizingMaskIntoConstraints = false
            hostView.addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: hostView.topAnchor),
                view.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
                view.bottomAnchor.constraint(equalTo: hostView.bottomAnchor)
            ])
            return
        }

        if panes.count == 1, let pane = panes.first, browserPanes.isEmpty {
            let view = pane.view
            view.translatesAutoresizingMaskIntoConstraints = false
            hostView.addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: hostView.topAnchor),
                view.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
                view.bottomAnchor.constraint(equalTo: hostView.bottomAnchor)
            ])
            return
        }

        // Build terminal pane layout
        let terminalSplitView: NSSplitView?
        if panes.count >= 2 {
            let splitView = buildSplitView(from: currentLayout)
            splitView.translatesAutoresizingMaskIntoConstraints = false
            terminalSplitView = splitView
        } else if let pane = panes.first {
            let wrapper = NSSplitView()
            wrapper.isVertical = true
            wrapper.dividerStyle = .thin
            pane.view.translatesAutoresizingMaskIntoConstraints = true
            wrapper.addSubview(pane.view)
            wrapper.translatesAutoresizingMaskIntoConstraints = false
            terminalSplitView = wrapper
        } else {
            terminalSplitView = nil
        }

        if browserPanes.isEmpty {
            if let splitView = terminalSplitView {
                hostView.addSubview(splitView)
                NSLayoutConstraint.activate([
                    splitView.topAnchor.constraint(equalTo: hostView.topAnchor),
                    splitView.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
                    splitView.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
                    splitView.bottomAnchor.constraint(equalTo: hostView.bottomAnchor)
                ])
                splitViews[UUID()] = splitView
            }
            return
        }

        // Build combined layout with browser panes
        let mainSplitView = NSSplitView()
        mainSplitView.isVertical = true
        mainSplitView.dividerStyle = .thin
        mainSplitView.translatesAutoresizingMaskIntoConstraints = false

        if let terminalSplit = terminalSplitView {
            mainSplitView.addSubview(terminalSplit)
        }

        for browserPane in browserPanes {
            let browserView = browserPane.view
            browserView.translatesAutoresizingMaskIntoConstraints = true
            mainSplitView.addSubview(browserView)
        }

        hostView.addSubview(mainSplitView)
        NSLayoutConstraint.activate([
            mainSplitView.topAnchor.constraint(equalTo: hostView.topAnchor),
            mainSplitView.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
            mainSplitView.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
            mainSplitView.bottomAnchor.constraint(equalTo: hostView.bottomAnchor)
        ])
        splitViews[UUID()] = mainSplitView
    }

    func restoreFromLayout(_ state: SessionState, window: NSWindow, manager: PaneManager) {
        let frame = state.windowFrame.nsRect
        if let screen = window.screen {
            window.setFrameOrigin(NSPoint(
                x: screen.frame.origin.x + frame.origin.x,
                y: screen.frame.origin.y + frame.origin.y
            ))
        }
        window.setContentSize(NSSize(width: frame.width, height: frame.height))

        for paneState in state.panes {
            var config = TerminalSurfaceConfiguration()
            config.executablePath = paneState.executablePath
            config.arguments = paneState.arguments
            config.workingDirectory = paneState.workingDirectory.map(URL.init(fileURLWithPath:))
            _ = manager.createPane(at: config)
        }
        manager.currentLayout = state.layout
        manager.rebuildLayout()
    }

    private func buildSplitView(from node: SplitNode) -> NSSplitView {
        switch node {
        case .pane(let index):
            let pane = panes[index]
            pane.view.translatesAutoresizingMaskIntoConstraints = true
            let wrapper = NSSplitView()
            wrapper.isVertical = true
            wrapper.dividerStyle = .thin
            wrapper.addSubview(pane.view)
            return wrapper

        case .split(let orientation, let ratio, let left, let right):
            let splitView = NSSplitView()
            splitView.isVertical = orientation == .vertical
            splitView.dividerStyle = .thin

            let leftView = buildLeafView(from: left)
            let rightView = buildLeafView(from: right)
            splitView.addSubview(leftView)
            splitView.addSubview(rightView)

            DispatchQueue.main.async {
                let totalWidth = splitView.bounds.width
                let totalHeight = splitView.bounds.height
                if orientation == .horizontal {
                    let leftWidth = totalWidth * ratio
                    splitView.setPosition(leftWidth, ofDividerAt: 0)
                } else {
                    let leftHeight = totalHeight * ratio
                    splitView.setPosition(leftHeight, ofDividerAt: 0)
                }
            }

            return splitView
        }
    }

    private func buildLeafView(from node: SplitNode) -> NSView {
        switch node {
        case .pane(let index):
            let pane = panes[index]
            pane.view.translatesAutoresizingMaskIntoConstraints = true
            return pane.view

        case .split(let orientation, let ratio, let left, let right):
            let splitView = NSSplitView()
            splitView.isVertical = orientation == .vertical
            splitView.dividerStyle = .thin

            let leftView = buildLeafView(from: left)
            let rightView = buildLeafView(from: right)
            splitView.addSubview(leftView)
            splitView.addSubview(rightView)

            DispatchQueue.main.async {
                let totalWidth = splitView.bounds.width
                let totalHeight = splitView.bounds.height
                if orientation == .horizontal {
                    let leftWidth = totalWidth * ratio
                    splitView.setPosition(leftWidth, ofDividerAt: 0)
                } else {
                    let leftHeight = totalHeight * ratio
                    splitView.setPosition(leftHeight, ofDividerAt: 0)
                }
            }

            return splitView
        }
    }

    var stateForPersistence: SessionState {
        let paneStates = panes.map { pane -> PaneState in
            let config = pane.configuration
            return PaneState(
                executablePath: config.executablePath ?? "/bin/zsh",
                arguments: config.arguments,
                workingDirectory: config.workingDirectory?.path,
                columns: 80,
                rows: 24
            )
        }
        return SessionState(panes: paneStates, layout: currentLayout)
    }

    private func replacePane(at targetIndex: Int, with replacement: SplitNode, in node: SplitNode) -> SplitNode {
        switch node {
        case .pane(let index):
            if index == targetIndex {
                return replacement
            }
            return node
        case .split(let orientation, let ratio, let left, let right):
            return .split(
                orientation: orientation,
                ratio: ratio,
                left: replacePane(at: targetIndex, with: replacement, in: left),
                right: replacePane(at: targetIndex, with: replacement, in: right)
            )
        }
    }

    private func rebuildLayoutTree() -> SplitNode {
        guard !panes.isEmpty else { return .pane(index: 0) }
        if panes.count == 1 { return .pane(index: 0) }

        var tree: SplitNode = .pane(index: 0)
        for i in 1..<panes.count {
            tree = .split(
                orientation: .horizontal,
                ratio: 0.5,
                left: tree,
                right: .pane(index: i)
            )
        }
        return tree
    }
}
