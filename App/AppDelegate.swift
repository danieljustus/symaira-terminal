import AppKit
import SwiftUI
import Combine
import GhosttyBridge
import TerminalCore
import AgentKit
import ProviderKit
import StackKit
import SymairaUI
import WorktreeKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var engine: GhosttyEngine?
    private var paneManager: PaneManager?
    private var oscEventHandler = OSCEventHandler()
    private var searchOverlay = ScrollbackSearchOverlay()
    private var tabBar: TabBarView?
    private var ghosttyConfig: GhosttyAppConfig?
    private var showSidebar = true
    private var mainSplitView: NSSplitView?
    private var sidebarHostingView: NSHostingView<AnyView>?
    private var sidebarViewModel: SidebarViewModel?
    private var monitorTask: Task<Void, Never>?
    private let workspaceMonitor = WorkspaceMonitor()
    private lazy var providerStore = ProviderStore()
    private lazy var stackStore = StackStore()
    private lazy var workspaceConfigManager = WorkspaceConfigManager(workspaceURL: URL(fileURLWithPath: NSHomeDirectory()))
    private var serviceProvider: TerminalServiceProvider?

    // Extracted coordinators
    private var backgroundServices: BackgroundServicesController?
    private let urlSchemeCoordinator = URLSchemeCoordinator()
    private let worktreePromptController = WorktreePromptController()
    private lazy var windowPresentation: WindowPresentationController = {
        WindowPresentationController(
            providerStore: providerStore,
            workspaceConfigManager: workspaceConfigManager,
            stackStore: stackStore
        )
    }()
    private lazy var workflowCoordinator: WorkflowCoordinator = {
        WorkflowCoordinator(paneManager: paneManager, sidebarViewModel: sidebarViewModel)
    }()

    // Update checker (GitHub release check, non-blocking)
    private lazy var updateCheckController = AppUpdateCheckController()

    // Saved at launch — self.window must not be accessed during termination
    // (use-after-free crash in objc_retain when AppKit tears down the window).
    private var savedWindowFrame: CodableRect?

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_: Notification) {
        UserDefaults.standard.register(defaults: [
            "keepAwakeAlways": false,
            "keepAwakeWhileAgentRunning": true
        ])
        SleepPreventionManager.shared.updateAssertionState()

        let config = GhosttyAppConfig.parse()
        self.ghosttyConfig = config

        let engine = GhosttyEngine()
        self.engine = engine

        let repoURL = URL(fileURLWithPath: NSHomeDirectory())
        let manager = PaneManager(engine: engine, repositoryURL: repoURL)
        self.paneManager = manager

        setupPaneCallbacks(manager: manager)
        workflowCoordinator.setupObservers()

        let serviceProvider = TerminalServiceProvider(paneManager: manager)
        self.serviceProvider = serviceProvider
        NSApp.servicesProvider = serviceProvider

        let bgServices = BackgroundServicesController(paneManager: manager)
        self.backgroundServices = bgServices
        bgServices.start()

        let window = createWindow()
        setupUI(window: window, manager: manager, repoURL: repoURL)
        restoreOrCreatePane(manager: manager, window: window)

        if !OnboardingView.isCompleted() {
            windowPresentation.showOnboarding()
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        manager.focusCurrent()
        saveWindowFrame(window)
        startMonitoring()
        triggerUpdateCheck()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool { true }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let paneManager else { return }
        urlSchemeCoordinator.dispatch(urls: urls, paneManager: paneManager)
    }

    func applicationWillTerminate(_: Notification) {
        monitorTask?.cancel()
        SleepPreventionManager.shared.deactivateAssertion()
        saveSession()
        paneManager?.panes.forEach { $0.close() }
        Task { await backgroundServices?.stop() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        .terminateNow
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleKeepAwake) {
            menuItem.state = UserDefaults.standard.bool(forKey: "keepAwakeAlways") ? .on : .off
        }
        return true
    }

    // MARK: - Window & UI Setup

    private func createWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Symaira Terminal"
        window.contentMinSize = NSSize(width: 480, height: 320)
        window.center()
        return window
    }

    private func setupUI(window: NSWindow, manager: PaneManager, repoURL: URL) {
        let tabBar = TabBarView()
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        tabBar.delegate = nil
        self.tabBar = tabBar

        let contentView = NSView(frame: window.contentLayoutRect)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = contentView

        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(splitView)
        self.mainSplitView = splitView

        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: contentView.topAnchor),
            splitView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        let worktreeStore = WorktreeStore(repositoryURL: repoURL)
        let viewModel = SidebarViewModel(worktreeStore: worktreeStore)
        self.sidebarViewModel = viewModel

        let sidebar = WorkspaceSidebar(
            viewModel: viewModel,
            onSelectPane: { [weak self] id in self?.selectPaneByID(id) },
            onOpenPort: { port in
                if let url = URL(string: "http://localhost:\(port)") { NSWorkspace.shared.open(url) }
            },
            onSelectWorktree: { [weak self] worktree in
                _ = self?.paneManager?.createPane(inDirectory: worktree.path)
            },
            onCreateWorktree: { [weak self, weak worktreeStore] in
                guard let self, let worktreeStore else { return }
                self.worktreePromptController.promptForWorktree(worktreeStore: worktreeStore) { taskID in
                    try worktreeStore.create(taskID: taskID)
                }
            },
            onRemoveWorktree: { [weak worktreeStore] worktree in
                let confirm = NSAlert()
                confirm.messageText = "Remove Worktree"
                confirm.informativeText = "Are you sure you want to remove worktree '\(worktree.taskID)'? This deletes the files and the branch."
                confirm.addButton(withTitle: "Remove")
                confirm.addButton(withTitle: "Cancel")
                if confirm.runModal() == .alertFirstButtonReturn {
                    try? worktreeStore?.remove(worktree)
                }
            }
        )

        let hostingView = NSHostingView(rootView: AnyView(sidebar))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        self.sidebarHostingView = hostingView
        splitView.addArrangedSubview(hostingView)
        hostingView.isHidden = !showSidebar

        let mainArea = NSView()
        mainArea.translatesAutoresizingMaskIntoConstraints = false
        splitView.addArrangedSubview(mainArea)

        mainArea.addSubview(tabBar)
        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: mainArea.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: mainArea.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: mainArea.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: 28)
        ])

        let paneContainer = NSView()
        paneContainer.translatesAutoresizingMaskIntoConstraints = false
        mainArea.addSubview(paneContainer)
        NSLayoutConstraint.activate([
            paneContainer.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            paneContainer.leadingAnchor.constraint(equalTo: mainArea.leadingAnchor),
            paneContainer.trailingAnchor.constraint(equalTo: mainArea.trailingAnchor),
            paneContainer.bottomAnchor.constraint(equalTo: mainArea.bottomAnchor)
        ])

        manager.attach(to: paneContainer)
        tabBar.delegate = self

        NSApp.mainMenu = AppMenuBuilder.buildMainMenu(target: self)
        setupUpdateBanner(mainArea: mainArea, paneContainer: paneContainer, tabBar: tabBar)
    }

    // MARK: - Update Check

    private func triggerUpdateCheck() {
        updateCheckController.checkForUpdate()
    }

    private func setupUpdateBanner(mainArea: NSView, paneContainer: NSView, tabBar: NSView) {
        let bannerView = UpdateBannerView(controller: updateCheckController)
        let hostingView = NSHostingView(rootView: bannerView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.setContentHuggingPriority(.required, for: .vertical)
        mainArea.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: mainArea.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: mainArea.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: mainArea.bottomAnchor)
        ])

        // Observe status changes to hide the banner when no update is available
        let observer = updateCheckController.$status.sink { [weak hostingView] (status: AppUpdateStatus) in
            if case .available = status {
                hostingView?.isHidden = false
            } else {
                hostingView?.isHidden = true
            }
        }
        // Initial visibility
        hostingView.isHidden = true
        _ = observer // Keep alive for the lifetime of the app
    }

    private func setupPaneCallbacks(manager: PaneManager) {
        manager.onPaneChanged = { [weak self] pane in
            self?.updateTitle(pane: pane)
            if let panes = self?.paneManager?.panes { self?.updateTabBar(panes: panes) }
            Task { [weak self] in await self?.updatePaneStatuses() }
        }
        manager.onPanesChanged = { [weak self] panes in
            self?.updateTabBar(panes: panes)
            Task { [weak self] in await self?.updatePaneStatuses() }
        }
        manager.onOSCTap = { [weak self] paneID, event in
            self?.oscEventHandler.handle(event, for: paneID)
        }
        oscEventHandler.onStatusChanged = { [weak self] paneID, status in
            self?.updateStatusRing(paneID: paneID, status: status)
        }
        oscEventHandler.onNotification = { title, body in
            NSLog("symaira notification: \(title) — \(body)")
        }
    }

    private func restoreOrCreatePane(manager: PaneManager, window: NSWindow) {
        if let saved = SessionPersistence.shared.load(), !saved.panes.isEmpty {
            manager.restoreFromLayout(saved, window: window, manager: manager)
        } else {
            _ = manager.createPane()
        }
        if manager.panes.isEmpty { _ = manager.createPane() }
    }

    private func saveWindowFrame(_ window: NSWindow) {
        if let screen = window.screen {
            let frame = window.frame
            let sf = screen.frame
            savedWindowFrame = CodableRect(NSRect(
                x: frame.origin.x - sf.origin.x,
                y: frame.origin.y - sf.origin.y,
                width: frame.width,
                height: frame.height
            ))
        }
    }

    private func saveSession() {
        guard let manager = paneManager else { return }
        var state = manager.stateForPersistence
        guard !state.panes.isEmpty else { return }
        if let frame = savedWindowFrame { state.windowFrame = frame }
        try? SessionPersistence.shared.saveImmediately(state)
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.updatePaneStatuses()
                guard let self else { break }
                let hasActive = await MainActor.run {
                    self.paneManager?.panes.contains { $0.agentStatus == .running || $0.agentStatus == .awaitingApproval } ?? false
                }
                if !hasActive { await MainActor.run { self.monitorTask = nil }; break }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func updatePaneStatuses() async {
        guard let manager = paneManager else { return }
        let parentMap = await workspaceMonitor.cachedProcessTree()
        let listeningPorts = await workspaceMonitor.cachedListeningPorts()

        var updatedItems: [PaneStatusInfo] = []
        for (index, pane) in manager.panes.enumerated() {
            let paneID = pane.paneID
            let title = oscEventHandler.title(for: paneID)
            let cwd = oscEventHandler.cwd(for: paneID) ?? pane.configuration.workingDirectory ?? URL(fileURLWithPath: NSHomeDirectory())
            let gitResult = await workspaceMonitor.cachedGitAndPRInfo(for: cwd, includePRInfo: pane === manager.currentPane)
            let shellPID = pane.pid
            let panePorts = listeningPorts.filter { WorkspaceMonitor.isDescendant(pid: $0.pid, parentPID: shellPID, parentMap: parentMap) }.map(\.port)

            updatedItems.append(PaneStatusInfo(
                id: paneID, index: index,
                title: title.isEmpty ? "Terminal" : title,
                status: pane.agentStatus, isActive: pane === manager.currentPane,
                cwd: cwd,
                gitBranch: gitResult.branch, gitIsDirty: gitResult.isDirty,
                gitAhead: gitResult.ahead, gitBehind: gitResult.behind,
                prNumber: gitResult.prNumber, prTitle: gitResult.prTitle, prStatus: gitResult.prStatus,
                listeningPorts: Array(Set(panePorts)).sorted()
            ))
        }
        if let store = sidebarViewModel?.worktreeStore { store.refreshDirtyState(for: store.worktrees) }
        await MainActor.run { self.sidebarViewModel?.paneItems = updatedItems; self.checkActiveAgents() }
    }

    private func checkActiveAgents() {
        guard let paneManager else { return }
        let hasActive = paneManager.panes.contains { $0.agentStatus == .running || $0.agentStatus == .awaitingApproval }
        SleepPreventionManager.shared.updateAgentActivityState(hasActiveAgent: hasActive)
        if hasActive && monitorTask == nil { startMonitoring() }
    }

    // MARK: - Pane Actions

    @objc private func newTab() {
        _ = paneManager?.createPane()
        paneManager?.focusCurrent()
    }

    @objc private func closeTab() {
        guard let current = paneManager?.currentPane else { return }
        closePaneOrWindow(current)
    }

    private func closePaneOrWindow(_ pane: TerminalPane) {
        guard let manager = paneManager else { return }
        if manager.panes.count <= 1 { window?.performClose(nil) } else { manager.closePane(pane) }
    }

    @objc private func splitHorizontal() { paneManager?.splitHorizontal() }
    @objc private func splitVertical() { paneManager?.splitVertical() }
    @objc private func focusNext() { paneManager?.focusNext() }
    @objc private func focusPrevious() { paneManager?.focusPrevious() }
    @objc private func focusNextActive() { paneManager?.focusNextActive() }
    @objc private func focusPreviousActive() { paneManager?.focusPreviousActive() }
    @objc private func focusBlocked() { paneManager?.focusLongestBlocked() }
    @objc private func focusLeft() { paneManager?.focus(in: .left) }
    @objc private func focusRight() { paneManager?.focus(in: .right) }
    @objc private func focusUp() { paneManager?.focus(in: .up) }
    @objc private func focusDown() { paneManager?.focus(in: .down) }
    @objc private func toggleZoom() { paneManager?.toggleZoom() }

    @objc private func forkSession() {
        guard let currentPane = paneManager?.currentPane else { return }
        _ = paneManager?.forkSession(from: currentPane)
    }

    @objc private func toggleSearch() {
        if searchOverlay.isVisible { searchOverlay.hide() } else if let pane = paneManager?.currentPane { searchOverlay.show(for: pane) }
    }

    @objc private func clearScrollback() {
        if let pane = paneManager?.currentPane {
            if let surface = pane.surface as? GhosttySurfaceController { surface.sendText("\u{1B}[3J") }
            pane.scrollbackBuffer.clear()
        }
    }

    @objc private func toggleSidebar() {
        showSidebar.toggle()
        sidebarHostingView?.isHidden = !showSidebar
        mainSplitView?.adjustSubviews()
    }

    @objc private func togglePalette() {
        // The palette owns its own dismissal, so tracking open/closed state here
        // too would desync the moment it closes by any other route and swallow
        // every second invocation.
        showCommandPalette()
    }

    @objc private func toggleKeepAwake() {
        let current = UserDefaults.standard.bool(forKey: "keepAwakeAlways")
        UserDefaults.standard.set(!current, forKey: "keepAwakeAlways")
        SleepPreventionManager.shared.updateAssertionState()
    }

    @objc private func showWorkflowCanvas() { workflowCoordinator.showWorkflowCanvas() }

    private func selectPaneByID(_ id: UUID) {
        guard let idx = paneManager?.panes.firstIndex(where: { $0.paneID == id }) else { return }
        paneManager?.selectPane(at: idx)
    }

    private func toggleDictation() {
        guard let currentPane = paneManager?.currentPane else { return }
        currentPane.inputEditor.toggleSTTRecording()
    }

    // MARK: - Window Presentation Wrappers

    @objc private func showSettings() { windowPresentation.showSettings() }
    @objc private func showSketchpad() { windowPresentation.showSketchpad() }
    @objc private func checkForUpdates() { updateCheckController.checkForUpdate() }
    @objc private func openHelpDocumentation() {
        if let url = URL(string: "https://github.com/danieljustus/symaira-terminal") {
            NSWorkspace.shared.open(url)
        }
    }

    private func showCommandPalette() {
        guard let window else { return }
        let items = [
            CommandPaletteItem(name: "New Tab", shortcut: "⌘T", category: "Tabs") { [weak self] in self?.newTab() },
            CommandPaletteItem(name: "New Workspace", shortcut: "⌘N", category: "Tabs") { [weak self] in self?.newTab() },
            CommandPaletteItem(name: "Close Tab", shortcut: "⌘W", category: "Tabs") { [weak self] in self?.closeTab() },
            CommandPaletteItem(name: "Split Vertically", shortcut: "⌘D", category: "Splits") { [weak self] in self?.splitVertical() },
            CommandPaletteItem(name: "Split Horizontally", shortcut: "⌘⇧D", category: "Splits") { [weak self] in self?.splitHorizontal() },
            CommandPaletteItem(name: "Find in Scrollback", shortcut: "⌘F", category: "Navigation") { [weak self] in self?.toggleSearch() },
            CommandPaletteItem(name: "Clear Scrollback", shortcut: "⌘K", category: "Navigation") { [weak self] in self?.clearScrollback() },
            CommandPaletteItem(name: "Next Pane", shortcut: "⌘]", category: "Navigation") { [weak self] in self?.focusNext() },
            CommandPaletteItem(name: "Previous Pane", shortcut: "⌘[", category: "Navigation") { [weak self] in self?.focusPrevious() },
            CommandPaletteItem(name: "Focus Left Pane", shortcut: "⌥⌘←", category: "Navigation") { [weak self] in self?.focusLeft() },
            CommandPaletteItem(name: "Focus Right Pane", shortcut: "⌥⌘→", category: "Navigation") { [weak self] in self?.focusRight() },
            CommandPaletteItem(name: "Focus Up Pane", shortcut: "⌥⌘↑", category: "Navigation") { [weak self] in self?.focusUp() },
            CommandPaletteItem(name: "Focus Down Pane", shortcut: "⌥⌘↓", category: "Navigation") { [weak self] in self?.focusDown() },
            CommandPaletteItem(name: "Toggle Pane Zoom", shortcut: "⌘⇧Enter", category: "Navigation") { [weak self] in self?.toggleZoom() },
            CommandPaletteItem(name: "Focus Blocked Agent", shortcut: "⌘⇧U", category: "Navigation") { [weak self] in self?.focusBlocked() },
            CommandPaletteItem(name: "Toggle Sidebar", shortcut: "⌘B", category: "View") { [weak self] in self?.toggleSidebar() },
            CommandPaletteItem(name: "Fork Session", shortcut: "⌘⇧F", category: "Session") { [weak self] in self?.forkSession() },
            CommandPaletteItem(name: "Toggle Dictation", shortcut: nil, category: "Input") { [weak self] in self?.toggleDictation() },
            CommandPaletteItem(name: "Open Sketchpad", shortcut: nil, category: "Input") { [weak self] in self?.showSketchpad() },
            CommandPaletteItem(name: "Open Workflow Canvas", shortcut: nil, category: "Workflow") { [weak self] in self?.showWorkflowCanvas() }
        ]
        windowPresentation.showCommandPalette(window: window, actions: items)
    }

    // MARK: - Title & Tab Bar

    private func updateTitle(pane: TerminalPane?) {
        guard let pane else { return }
        let title = oscEventHandler.title(for: pane.paneID)
        window?.title = title.isEmpty ? "Symaira Terminal" : "\(title) — Symaira Terminal"
    }

    private func updateTabBar(panes: [TerminalPane]) {
        let titles = panes.enumerated().map { index, pane in
            let title = oscEventHandler.title(for: pane.paneID)
            return title.isEmpty ? "Tab \(index + 1)" : title
        }
        let selectedIndex = panes.firstIndex(where: { $0 === paneManager?.currentPane }) ?? 0
        tabBar?.updateTabs(titles: titles, selectedIndex: selectedIndex)
    }

    private func updateStatusRing(paneID: UUID, status: AgentStatus) {
        guard let pane = paneManager?.panes.first(where: { $0.paneID == paneID }) else { return }
        pane.updateStatus(status)
        checkActiveAgents()
    }
}

// MARK: - TabBarDelegate

extension AppDelegate: @preconcurrency TabBarDelegate {
    func tabBarDidSelectTab(_ tabBar: TabBarView, index: Int) {
        paneManager?.selectPane(at: index)
    }

    func tabBarDidRequestClose(_ tabBar: TabBarView, index: Int) {
        guard let paneManager, index < paneManager.panes.count else { return }
        closePaneOrWindow(paneManager.panes[index])
    }
}
