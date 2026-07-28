import AppKit
import GhosttyBridge
import SymairaUI
import TerminalCore
import WorktreeKit
import UserNotifications

@MainActor
final class PaneManager {
    /// All open tabs. Each tab owns its own panes and split layout.
    private(set) var tabs: [Tab] = []
    /// Index into `tabs` for the currently visible tab.
    private(set) var currentTabIndex: Int = 0
    private(set) var browserPanes: [BrowserPane] = []
    private(set) var currentPane: TerminalPane?
    private(set) var zoomedPane: TerminalPane?

    /// Flat list of ALL terminal panes across all tabs, for backward compatibility.
    var panes: [TerminalPane] {
        tabs.flatMap(\.panes)
    }

    /// The currently active tab.
    var currentTab: Tab? {
        guard !tabs.isEmpty, currentTabIndex < tabs.count else { return nil }
        return tabs[currentTabIndex]
    }

    let engine: GhosttyEngine
    private weak var hostView: NSView?
    private var oscParsers: [UUID: OSCStreamParser] = [:]
    var worktreeManager: WorktreeManager?

    /// Test hook: override to control NSAlert responses without displaying UI.
    var alertRunner: ((NSAlert) -> NSApplication.ModalResponse)?

    var onPaneChanged: ((TerminalPane?) -> Void)?
    var onPanesChanged: (([TerminalPane]) -> Void)?
    var onTabsChanged: (() -> Void)?
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

    // MARK: - Tab Management

    /// Create a new tab with one terminal pane. The new tab becomes current.
    @discardableResult
    func newTab() -> Tab {
        let tab = Tab(title: "Terminal")
        let pane = createPaneInternal(in: tab)
        tab.panes.append(pane)
        tab.currentPaneIndex = 0
        tab.currentLayout = .pane(index: 0)
        tabs.append(tab)
        currentTabIndex = tabs.count - 1
        currentPane = pane
        onPaneChanged?(pane)
        onTabsChanged?()
        onPanesChanged?(panes)
        rebuildLayout(for: tab)
        focusSurface(of: pane)
        return tab
    }

    /// Select a tab by index. The tab's current pane becomes the active pane.
    func selectTab(at index: Int) {
        guard index >= 0, index < tabs.count else { return }
        currentTabIndex = index
        guard let tab = currentTab else { return }
        currentPane = tab.currentPane ?? tab.panes.first
        if let pane = currentPane {
            onPaneChanged?(pane)
            focusSurface(of: pane)
        }
        rebuildLayout(for: tab)
        onTabsChanged?()
    }

    /// Close the tab at the given index and all its panes.
    func closeTab(at index: Int) {
        guard index >= 0, index < tabs.count else { return }
        let tab = tabs[index]

        // Close all pane surfaces in the tab
        for pane in tab.panes {
            if zoomedPane === pane { zoomedPane = nil }
            pane.close()
            oscParsers.removeValue(forKey: pane.paneID)
        }

        tabs.remove(at: index)

        if tabs.isEmpty {
            currentPane = nil
            currentTabIndex = 0
            onPaneChanged?(nil)
            onPanesChanged?(panes)
            onTabsChanged?()
            // No panes left — the caller should close the window
            return
        }

        // Select the nearest tab
        currentTabIndex = min(index, tabs.count - 1)
        if let newTab = currentTab {
            currentPane = newTab.currentPane ?? newTab.panes.first
            rebuildLayout(for: newTab)
            if let pane = currentPane {
                onPaneChanged?(pane)
                focusSurface(of: pane)
            }
        }
        onTabsChanged?()
        onPanesChanged?(panes)
    }

    /// Close the current tab (closing the window if it was the last).
    func closeCurrentTab() {
        guard let tab = currentTab else { return }
        let tabIdx = currentTabIndex
        // If this is the last tab, close the window
        if tabs.count <= 1 {
            hostView?.window?.performClose(nil)
            return
        }
        closeTab(at: tabIdx)
    }

    // MARK: - Pane Management

    /// Create a pane in the current tab. Creates the first tab if none exist.
    @discardableResult
    func createPane(at configuration: TerminalSurfaceConfiguration? = nil) -> TerminalPane {
        // Auto-create first tab if no tabs exist
        if tabs.isEmpty {
            let tab = Tab(title: "Terminal")
            tabs.append(tab)
            currentTabIndex = 0
        }
        guard let tab = currentTab else {
            fatalError("PaneManager has no tab to create a pane in")
        }
        let pane = createPaneInternal(at: configuration)
        tab.panes.append(pane)
        // Update the layout to point to the new pane within this tab's index space
        let paneIdx = tab.panes.count - 1
        if tab.panes.count == 1 {
            tab.currentLayout = .pane(index: 0)
        }
        currentPane = pane
        tab.currentPaneIndex = paneIdx
        onPanesChanged?(panes)
        onPaneChanged?(pane)
        rebuildLayout(for: tab)
        return pane
    }

    @discardableResult
    func createPane(inDirectory directory: URL) -> TerminalPane {
        var config = defaultConfiguration()
        config.workingDirectory = directory
        return createPane(at: config)
    }

    /// Internal: creates the surface and wires OSC output, but does NOT add
    /// the pane to any tab. The caller is responsible for appending to a tab's
    /// `panes` array and updating the layout.
    private func createPaneInternal(at configuration: TerminalSurfaceConfiguration? = nil, in tab: Tab? = nil) -> TerminalPane {
        let config = configuration ?? defaultConfiguration()
        let surface: (any TerminalSurface)?
        do {
            surface = try engine.makeSurface(configuration: config)
        } catch {
            NSLog("symaira: failed to create terminal surface: %@", String(describing: error))
            let content = UNMutableNotificationContent()
            content.title = "Terminal Error"
            content.body = "Could not create terminal surface: \(error.localizedDescription)"
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
            surface = nil
        }
        let pane = TerminalPane(surface: surface, configuration: config)
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

        return pane
    }

    /// Create a pane and add it to the given tab (for restore/setup use).
    @discardableResult
    func createPane(at configuration: TerminalSurfaceConfiguration? = nil, in tab: Tab) -> TerminalPane {
        let pane = createPaneInternal(at: configuration, in: tab)
        tab.panes.append(pane)
        return pane
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

        let tab = findTab(for: currentPane)
        if let existingSplit = findSplitView(for: currentPane, in: tab) {
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
            tab?.splitViews[UUID()] = splitView
        }

        return browserPane
    }

    func closeBrowserPane(_ browserPane: BrowserPane) {
        guard let idx = browserPanes.firstIndex(where: { $0 === browserPane }) else { return }
        browserPane.close()
        browserPanes.remove(at: idx)
        rebuildLayout(for: currentTab)
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

        // Find which tab this pane belongs to
        guard let (tab, paneIdx) = findTabAndIndex(for: pane) else { return }

        guard tab.panes.count > 1 else {
            // Last pane in tab — close the entire tab
            guard let tabIdx = tabs.firstIndex(where: { $0 === tab }) else { return }
            if tabs.count <= 1 {
                // Last tab — close the window
                pane.close()
                tab.panes.removeAll()
                tab.currentPaneIndex = 0
                currentPane = nil
                onPanesChanged?(panes)
                onPaneChanged?(nil)
                hostView?.window?.performClose(nil)
                return
            }
            // Close the tab (handles selection of next tab)
            pane.close()
            tab.panes.removeAll()
            closeTab(at: tabIdx)
            return
        }

        // Detach the closed pane's views before tearing down the surface
        pane.view.removeFromSuperview()
        pane.close()
        tab.panes.remove(at: paneIdx)
        oscParsers.removeValue(forKey: pane.paneID)

        if currentPane === pane {
            let newIdx = min(paneIdx, tab.panes.count - 1)
            tab.currentPaneIndex = newIdx
            currentPane = tab.panes[safe: newIdx] ?? tab.panes.first
        }

        // Collapse the pane out of the tab's layout tree
        tab.currentLayout = tab.currentLayout.removingPane(at: paneIdx) ?? .pane(index: 0)

        onPanesChanged?(panes)
        if let cp = currentPane {
            onPaneChanged?(cp)
        }
        rebuildLayout(for: tab)
    }

    func focusNext() {
        guard let tab = currentTab, tab.panes.count > 1 else { return }
        guard let cur = currentPane, let idx = tab.panes.firstIndex(where: { $0 === cur }) else { return }
        let next = tab.panes[(idx + 1) % tab.panes.count]
        currentPane = next
        tab.currentPaneIndex = idx + 1 < tab.panes.count ? idx + 1 : 0
        onPaneChanged?(next)
        focusSurface(of: next)
    }

    func focusPrevious() {
        guard let tab = currentTab, tab.panes.count > 1 else { return }
        guard let cur = currentPane, let idx = tab.panes.firstIndex(where: { $0 === cur }) else { return }
        let prev = tab.panes[(idx - 1 + tab.panes.count) % tab.panes.count]
        currentPane = prev
        tab.currentPaneIndex = idx > 0 ? idx - 1 : tab.panes.count - 1
        onPaneChanged?(prev)
        focusSurface(of: prev)
    }

    func selectPane(at index: Int) {
        // Find the pane across all tabs by flat index
        var flatIdx = 0
        for (tabIdx, tab) in tabs.enumerated() {
            if index < flatIdx + tab.panes.count {
                let paneIdx = index - flatIdx
                let pane = tab.panes[paneIdx]
                currentTabIndex = tabIdx
                tab.currentPaneIndex = paneIdx
                currentPane = pane
                rebuildLayout(for: tab)
                onPaneChanged?(pane)
                onTabsChanged?()
                focusSurface(of: pane)
                return
            }
            flatIdx += tab.panes.count
        }
    }

    /// Make the libghostty surface the first responder so keystrokes reach the
    /// PTY. Focusing the wrapper `pane.view` (a plain container NSView) does not
    /// forward key events to the Metal surface, so the terminal would silently
    /// swallow input. Falls back to the container only if the surface is absent.
    private func focusSurface(of pane: TerminalPane) {
        let target: NSView
        if let ghosttySurface = pane.surface as? GhosttySurfaceController {
            target = ghosttySurface.view
        } else {
            target = pane.view
        }
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
        guard let currentPane = currentPane, let tab = currentTab, tab.panes.count > 1 else { return }

        let currentFrame = currentPane.view.convert(currentPane.view.bounds, to: nil)
        let currentCenter = NSPoint(x: currentFrame.midX, y: currentFrame.midY)

        var bestCandidate: TerminalPane?
        var minDistance = Double.infinity

        for pane in tab.panes {
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
                if dy > 1 {
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
                let dist = primaryDelta + 4.0 * abs(secondaryDelta)
                if dist < minDistance {
                    minDistance = dist
                    bestCandidate = pane
                }
            }
        }

        if let target = bestCandidate, let idx = tab.panes.firstIndex(where: { $0 === target }) {
            currentPane = target
            tab.currentPaneIndex = idx
            selectPane(at: panes.firstIndex(where: { $0 === target }) ?? 0)
        }
    }

    // MARK: - Zoom (Maximize / Restore)

    func toggleZoom() {
        guard let tab = currentTab else { return }
        if tab.zoomedPane != nil {
            tab.zoomedPane = nil
            zoomedPane = nil
        } else if let cur = currentPane {
            tab.zoomedPane = cur
            zoomedPane = cur
        }
        rebuildLayout(for: tab)
    }

    func splitHorizontal() {
        split(orientation: .horizontal)
    }

    func splitVertical() {
        split(orientation: .vertical)
    }

    private func split(orientation: SplitOrientation) {
        guard let tab = currentTab, let cur = currentPane, hostView != nil else { return }
        guard let curIdx = tab.panes.firstIndex(where: { $0 === cur }) else { return }

        // Create a new pane and add it to the current tab
        let newPane = createPaneInternal(in: tab)
        tab.panes.append(newPane)
        let newIdx = tab.panes.count - 1

        // Record the split in the tab's layout tree
        tab.currentLayout = replacePane(
            at: curIdx,
            with: .split(
                orientation: orientation,
                ratio: 0.5,
                left: .pane(index: curIdx),
                right: .pane(index: newIdx)
            ),
            in: tab.currentLayout
        )

        tab.currentPaneIndex = newIdx
        currentPane = newPane
        rebuildLayout(for: tab)
        onPaneChanged?(newPane)
        onPanesChanged?(panes)
    }

    private func findSplitView(for pane: TerminalPane, in tab: Tab?) -> NSSplitView? {
        let views = tab?.splitViews ?? [:]
        for (_, splitView) in views where splitView.subviews.contains(where: { $0 === pane.view }) {
            return splitView
        }
        return nil
    }

    // MARK: - Layout

    func rebuildLayout() {
        // Default to current tab; useful when called from external setters.
        rebuildLayout(for: currentTab)
    }

    func rebuildLayout(for tab: Tab?) {
        guard let hostView else { return }
        guard let tab else {
            hostView.subviews.forEach { $0.removeFromSuperview() }
            return
        }

        hostView.subviews.forEach { $0.removeFromSuperview() }
        tab.splitViews.removeAll()

        if let zoomed = tab.zoomedPane, tab.panes.contains(where: { $0 === zoomed }) {
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

        if tab.panes.count == 1, let pane = tab.panes.first, browserPanes.isEmpty {
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

        // Build terminal pane layout for this tab
        let terminalSplitView: NSSplitView?
        if tab.panes.count >= 2 {
            let splitView = buildSplitView(from: tab.currentLayout, in: tab)
            splitView.translatesAutoresizingMaskIntoConstraints = false
            terminalSplitView = splitView
        } else if let pane = tab.panes.first {
            let wrapper = NSSplitView()
            wrapper.isVertical = true
            wrapper.dividerStyle = .thin
            pane.view.translatesAutoresizingMaskIntoConstraints = true
            pane.view.clipsToBounds = true
            wrapper.addArrangedSubview(pane.view)
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
                tab.splitViews[UUID()] = splitView
            }
            return
        }

        // Build combined layout with browser panes
        let mainSplitView = NSSplitView()
        mainSplitView.isVertical = true
        mainSplitView.dividerStyle = .thin
        mainSplitView.translatesAutoresizingMaskIntoConstraints = false

        if let terminalSplit = terminalSplitView {
            mainSplitView.addArrangedSubview(terminalSplit)
        }

        for browserPane in browserPanes {
            let browserView = browserPane.view
            browserView.translatesAutoresizingMaskIntoConstraints = true
            mainSplitView.addArrangedSubview(browserView)
        }

        hostView.addSubview(mainSplitView)
        NSLayoutConstraint.activate([
            mainSplitView.topAnchor.constraint(equalTo: hostView.topAnchor),
            mainSplitView.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
            mainSplitView.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
            mainSplitView.bottomAnchor.constraint(equalTo: hostView.bottomAnchor)
        ])
        tab.splitViews[UUID()] = mainSplitView
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

        // Prefer the new multi-tab format
        if let tabStates = state.tabs, !tabStates.isEmpty {
            var createdFirst = false
            for tabState in tabStates {
                let tab = Tab(title: tabState.title)
                for paneState in tabState.panes {
                    var config = TerminalSurfaceConfiguration()
                    config.executablePath = paneState.executablePath
                    config.arguments = paneState.arguments
                    config.workingDirectory = paneState.workingDirectory.map(URL.init(fileURLWithPath:))
                    let pane = createPane(at: config, in: tab)
                    // createPane(at:in:) already appends to tab.panes
                    if !createdFirst {
                        currentPane = pane
                        createdFirst = true
                    }
                }
                tab.currentLayout = tabState.layout
                tab.currentPaneIndex = 0
                tabs.append(tab)
            }
            currentTabIndex = 0
            if tabs.isEmpty {
                _ = newTab()
            }
            rebuildLayout(for: currentTab)
            return
        }

        // Legacy flat format — wrap all panes into one tab
        let tab = Tab(title: "Terminal")
        for paneState in state.panes {
            var config = TerminalSurfaceConfiguration()
            config.executablePath = paneState.executablePath
            config.arguments = paneState.arguments
            config.workingDirectory = paneState.workingDirectory.map(URL.init(fileURLWithPath:))
            _ = createPane(at: config, in: tab)
            // createPane(at:in:) already appends to tab.panes
        }

        // A persisted session can legitimately contain zero panes — e.g. the
        // user closed the last tab before quitting. Restoring it verbatim would
        // leave an empty, inert window that renders nothing and swallows every
        // keystroke. Guarantee at least one usable pane so the app is never
        // dead on launch.
        if tab.panes.isEmpty {
            let pane = createPaneInternal(in: tab)
            tab.panes.append(pane)
            tab.currentLayout = .pane(index: 0)
            currentPane = pane
        } else {
            tab.currentLayout = state.layout
            currentPane = tab.panes.first
        }

        tab.currentPaneIndex = tab.panes.firstIndex(where: { $0 === currentPane }) ?? 0
        tabs.append(tab)
        currentTabIndex = 0
        rebuildLayout(for: tab)
    }

    private func buildSplitView(from node: SplitNode, in tab: Tab) -> NSSplitView {
        switch node {
        case .pane:
            let wrapper = NSSplitView()
            wrapper.isVertical = true
            wrapper.dividerStyle = .thin
            wrapper.addArrangedSubview(buildLeafView(from: node, in: tab))
            return wrapper

        case .split:
            guard let splitView = buildLeafView(from: node, in: tab) as? NSSplitView else {
                return NSSplitView()
            }
            return splitView
        }
    }

    private func buildLeafView(from node: SplitNode, in tab: Tab) -> NSView {
        switch node {
        case .pane(let index):
            let pane = tab.panes[index]
            pane.view.translatesAutoresizingMaskIntoConstraints = true
            pane.view.clipsToBounds = true
            return pane.view

        case .split(let orientation, let ratio, let left, let right):
            let splitView = NSSplitView()
            splitView.isVertical = orientation == .vertical
            splitView.dividerStyle = .thin
            splitView.addArrangedSubview(buildLeafView(from: left, in: tab))
            splitView.addArrangedSubview(buildLeafView(from: right, in: tab))
            applyDividerPosition(splitView, orientation: orientation, ratio: ratio)
            return splitView
        }
    }

    private func applyDividerPosition(
        _ splitView: NSSplitView,
        orientation: SplitOrientation,
        ratio: Double
    ) {
        DispatchQueue.main.async { [weak splitView] in
            guard let splitView, splitView.arrangedSubviews.count >= 2 else { return }
            splitView.layoutSubtreeIfNeeded()
            let total = orientation.measuresAlongWidth
                ? splitView.bounds.width
                : splitView.bounds.height
            guard total > 0 else { return }
            splitView.setPosition(total * ratio, ofDividerAt: 0)
        }
    }

    var stateForPersistence: SessionState {
        let tabStates = tabs.map { tab -> TabState in
            let paneStates = tab.panes.map { pane -> PaneState in
                let config = pane.configuration
                return PaneState(
                    executablePath: config.executablePath ?? "/bin/zsh",
                    arguments: config.arguments,
                    workingDirectory: config.workingDirectory?.path,
                    columns: 80,
                    rows: 24
                )
            }
            return TabState(panes: paneStates, layout: tab.currentLayout, title: tab.title)
        }
        return SessionState(
            panes: [],
            layout: .pane(index: 0),
            tabs: tabStates,
            windowFrame: CodableRect(x: 0, y: 0, width: 960, height: 600)
        )
    }

    // MARK: - Helpers

    /// Find the tab that contains the given pane.
    private func findTab(for pane: TerminalPane) -> Tab? {
        tabs.first { $0.panes.contains(where: { $0 === pane }) }
    }

    /// Find the tab and local pane index for a given pane.
    private func findTabAndIndex(for pane: TerminalPane) -> (tab: Tab, index: Int)? {
        for tab in tabs {
            if let idx = tab.panes.firstIndex(where: { $0 === pane }) {
                return (tab, idx)
            }
        }
        return nil
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
}

// MARK: - Safe array access

extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
