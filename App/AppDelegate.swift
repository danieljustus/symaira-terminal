import AppKit
import SwiftUI
import GhosttyBridge
import TerminalCore
import AgentKit
import ProviderKit
import StackKit
import SymairaUI
import WorktreeKit
import ControlKit
import MCPKit

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
    private var showPalette = false
    private var sidebarItem: NSSplitViewItem?
    private var sidebarViewController: NSViewController?
    private var mainSplitView: NSSplitView?
    private var sidebarHostingView: NSHostingView<AnyView>?
    private var mainAreaView: NSView?
    private var sidebarViewModel: SidebarViewModel?
    private var monitorTask: Task<Void, Never>?
    private let workspaceMonitor = WorkspaceMonitor()
    private lazy var providerStore = ProviderStore()
    private lazy var stackStore = StackStore()
    private lazy var workspaceConfigManager = WorkspaceConfigManager(workspaceURL: URL(fileURLWithPath: NSHomeDirectory()))
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var sketchpadWindow: NSWindow?
    private var serviceProvider: TerminalServiceProvider?
    private var controlAdapter: OrchestrationControlAdapter?
    private var controlServer: ControlServer?
    private var mcpServer: MCPServer?
    private lazy var workflowCoordinator: WorkflowCoordinator = {
        WorkflowCoordinator(paneManager: paneManager, sidebarViewModel: sidebarViewModel)
    }()

    // Saved at launch — self.window must not be accessed during termination
    // (use-after-free crash in objc_retain when AppKit tears down the window).
    private var savedWindowFrame: CodableRect?

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

        manager.onPaneChanged = { [weak self] pane in
            self?.updateTitle(pane: pane)
            if let panes = self?.paneManager?.panes {
                self?.updateTabBar(panes: panes)
            }
            Task { [weak self] in
                await self?.updatePaneStatuses()
            }
        }
        manager.onPanesChanged = { [weak self] panes in
            self?.updateTabBar(panes: panes)
            Task { [weak self] in
                await self?.updatePaneStatuses()
            }
        }
        manager.onOSCTap = { [weak self] paneID, event in
            self?.oscEventHandler.handle(event, for: paneID)
        }

        workflowCoordinator.setupObservers()

        oscEventHandler.onStatusChanged = { [weak self] paneID, status in
            self?.updateStatusRing(paneID: paneID, status: status)
        }
        oscEventHandler.onNotification = { title, body in
            NSLog("symaira notification: \(title) — \(body)")
        }

        let serviceProvider = TerminalServiceProvider(paneManager: manager)
        self.serviceProvider = serviceProvider
        NSApp.servicesProvider = serviceProvider

        startControlSurface(paneManager: manager)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Symaira Terminal"
        window.contentMinSize = NSSize(width: 480, height: 320)
        window.center()

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

        // Sidebar View Setup
        let worktreeStore = WorktreeStore(repositoryURL: repoURL)
        let viewModel = SidebarViewModel(worktreeStore: worktreeStore)
        self.sidebarViewModel = viewModel

        let sidebar = WorkspaceSidebar(
            viewModel: viewModel,
            onSelectPane: { [weak self] id in
                self?.selectPaneByID(id)
            },
            onOpenPort: { port in
                if let url = URL(string: "http://localhost:\(port)") {
                    NSWorkspace.shared.open(url)
                }
            },
            onSelectWorktree: { [weak self] worktree in
                _ = self?.paneManager?.createPane(inDirectory: worktree.path)
            },
            onCreateWorktree: { [weak worktreeStore] in
                let alert = NSAlert()
                alert.messageText = "Create New Worktree"
                alert.informativeText = "Enter task ID (alphanumeric only):"
                let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
                alert.accessoryView = input
                alert.addButton(withTitle: "Create")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn {
                    let taskID = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !taskID.isEmpty {
                        do {
                            _ = try worktreeStore?.create(taskID: taskID)
                        } catch {
                            let errorAlert = NSAlert(error: error)
                            errorAlert.runModal()
                        }
                    }
                }
            },
            onRemoveWorktree: { [weak worktreeStore] worktree in
                let confirm = NSAlert()
                confirm.messageText = "Remove Worktree"
                confirm.informativeText = "Are you sure you want to remove worktree '\(worktree.taskID)'? This deletes the files and the branch."
                confirm.addButton(withTitle: "Remove")
                confirm.addButton(withTitle: "Cancel")
                if confirm.runModal() == .alertFirstButtonReturn {
                    do {
                        try worktreeStore?.remove(worktree)
                    } catch {
                        let errorAlert = NSAlert(error: error)
                        errorAlert.runModal()
                    }
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
        self.mainAreaView = mainArea
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

        setupKeyboardShortcuts(window: window)

        if let saved = SessionPersistence.shared.load(), !saved.panes.isEmpty {
            restoreSession(saved, window: window, manager: manager)
        } else {
            _ = manager.createPane()
        }

        // Final safety net: no matter what the restore path did, the app must
        // launch with a live terminal. An empty main area produces a window that
        // accepts no input and cannot spawn a shell — the failure reported in
        // v0.8.1, caused by a persisted session with zero panes.
        if manager.panes.isEmpty {
            _ = manager.createPane()
        }

        if !UserDefaults.standard.bool(forKey: "onboardingCompleted") {
            showOnboarding()
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window

        // The window is on screen now, so the terminal surface can finally
        // become first responder — without this the initial pane never receives
        // keyboard focus and the terminal appears unresponsive on launch.
        manager.focusCurrent()

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

        startMonitoring()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let handler = URLSchemeHandler()
        for url in urls {
            guard let command = handler.parse(url) else { continue }
            switch command {
            case .openDirectory(let directory):
                _ = paneManager?.createPane(inDirectory: directory)
            case .openTab(let command, let workingDirectory):
                if let command, !command.isEmpty {
                    Task {
                        _ = await paneManager?.openTab(command: command, workingDirectory: workingDirectory)
                    }
                } else if let workingDirectory {
                    _ = paneManager?.createPane(inDirectory: workingDirectory)
                } else {
                    _ = paneManager?.createPane()
                }
            }
        }
    }

    func applicationWillTerminate(_: Notification) {
        monitorTask?.cancel()
        SleepPreventionManager.shared.deactivateAssertion()
        saveSession()
        paneManager?.panes.forEach { $0.close() }
        Task {
            await controlServer?.stop()
            await mcpServer?.stop()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        .terminateNow
    }

    private func saveSession() {
        guard let manager = paneManager else { return }
        var state = manager.stateForPersistence
        // Never overwrite a good session with a paneless one. Restoring zero
        // panes strands the user in an empty window, so if every tab is already
        // closed we keep the previous session on disk instead.
        guard !state.panes.isEmpty else { return }
        if let frame = savedWindowFrame {
            state.windowFrame = frame
        }
        try? SessionPersistence.shared.save(state)
    }

    private func startControlSurface(paneManager: PaneManager) {
        let controlAdapter = OrchestrationControlAdapter(paneManager: paneManager)
        self.controlAdapter = controlAdapter

        let controlServer = ControlServer()
        self.controlServer = controlServer
        Task {
            do {
                try await controlServer.start(provider: controlAdapter)
                let path = await controlServer.socketPath
                NSLog("symaira: control server listening at %@", path)
            } catch {
                NSLog("symaira: failed to start control server: %@", String(describing: error))
            }
        }

        let mcpServer = MCPServer()
        self.mcpServer = mcpServer
        Task {
            do {
                try await mcpServer.start(provider: controlAdapter)
                let path = await mcpServer.socketPath
                NSLog("symaira: mcp server listening at %@", path)
            } catch {
                NSLog("symaira: failed to start mcp server: %@", String(describing: error))
            }
        }
    }

    private func restoreSession(_ state: SessionState, window: NSWindow, manager: PaneManager) {
        manager.restoreFromLayout(state, window: window, manager: manager)
    }

    // MARK: - Keyboard Shortcuts

    private func setupKeyboardShortcuts(window: NSWindow) {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(
            title: "About Symaira Terminal",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        ))
        appMenu.addItem(.separator())
        let keepAwakeItem = NSMenuItem(title: "Keep Mac Awake", action: #selector(toggleKeepAwake), keyEquivalent: "")
        keepAwakeItem.target = self
        appMenu.addItem(keepAwakeItem)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(NSMenuItem(title: "Quit Symaira Terminal", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let appMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenu = NSMenu(title: "File")
        let newTabItem = NSMenuItem(title: "New Tab", action: #selector(newTab), keyEquivalent: "t")
        newTabItem.keyEquivalentModifierMask = [.command]
        newTabItem.target = self
        fileMenu.addItem(newTabItem)

        let newWorkspaceItem = NSMenuItem(title: "New Workspace", action: #selector(newTab), keyEquivalent: "n")
        newWorkspaceItem.keyEquivalentModifierMask = [.command]
        newWorkspaceItem.target = self
        fileMenu.addItem(newWorkspaceItem)

        let closeTabItem = NSMenuItem(title: "Close Tab", action: #selector(closeTab), keyEquivalent: "w")
        closeTabItem.keyEquivalentModifierMask = [.command]
        closeTabItem.target = self
        fileMenu.addItem(closeTabItem)

        fileMenu.addItem(.separator())

        let splitHItem = NSMenuItem(title: "Split Horizontally", action: #selector(splitHorizontal), keyEquivalent: "D")
        splitHItem.keyEquivalentModifierMask = [.command, .shift]
        splitHItem.target = self
        fileMenu.addItem(splitHItem)

        let splitVItem = NSMenuItem(title: "Split Vertically", action: #selector(splitVertical), keyEquivalent: "d")
        splitVItem.keyEquivalentModifierMask = [.command]
        splitVItem.target = self
        fileMenu.addItem(splitVItem)

        fileMenu.addItem(.separator())

        let searchItem = NSMenuItem(title: "Find in Scrollback", action: #selector(toggleSearch), keyEquivalent: "f")
        searchItem.keyEquivalentModifierMask = [.command]
        searchItem.target = self
        fileMenu.addItem(searchItem)

        let clearScrollbackItem = NSMenuItem(title: "Clear Scrollback", action: #selector(clearScrollback), keyEquivalent: "k")
        clearScrollbackItem.keyEquivalentModifierMask = [.command]
        clearScrollbackItem.target = self
        fileMenu.addItem(clearScrollbackItem)

        let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let viewMenu = NSMenu(title: "View")

        let paletteItem = NSMenuItem(title: "Command Palette", action: #selector(togglePalette), keyEquivalent: "p")
        paletteItem.keyEquivalentModifierMask = [.command, .shift]
        paletteItem.target = self
        viewMenu.addItem(paletteItem)

        let toggleSidebarItem = NSMenuItem(title: "Toggle Sidebar", action: #selector(toggleSidebar), keyEquivalent: "b")
        toggleSidebarItem.keyEquivalentModifierMask = [.command]
        toggleSidebarItem.target = self
        viewMenu.addItem(toggleSidebarItem)

        viewMenu.addItem(.separator())

        let focusNextItem = NSMenuItem(title: "Next Pane", action: #selector(focusNext), keyEquivalent: "]")
        focusNextItem.keyEquivalentModifierMask = [.command]
        focusNextItem.target = self
        viewMenu.addItem(focusNextItem)

        let focusPrevItem = NSMenuItem(title: "Previous Pane", action: #selector(focusPrevious), keyEquivalent: "[")
        focusPrevItem.keyEquivalentModifierMask = [.command]
        focusPrevItem.target = self
        viewMenu.addItem(focusPrevItem)

        let focusNextActiveItem = NSMenuItem(title: "Focus Next Active Agent", action: #selector(focusNextActive), keyEquivalent: "u")
        focusNextActiveItem.keyEquivalentModifierMask = [.command, .shift]
        focusNextActiveItem.target = self
        viewMenu.addItem(focusNextActiveItem)

        let focusPrevActiveItem = NSMenuItem(title: "Focus Previous Active Agent", action: #selector(focusPreviousActive), keyEquivalent: "i")
        focusPrevActiveItem.keyEquivalentModifierMask = [.command, .shift]
        focusPrevActiveItem.target = self
        viewMenu.addItem(focusPrevActiveItem)

        viewMenu.addItem(.separator())

        let focusLeftItem = NSMenuItem(title: "Focus Left Pane", action: #selector(focusLeft), keyEquivalent: "\u{F702}")
        focusLeftItem.keyEquivalentModifierMask = [.command, .option]
        focusLeftItem.target = self
        viewMenu.addItem(focusLeftItem)

        let focusRightItem = NSMenuItem(title: "Focus Right Pane", action: #selector(focusRight), keyEquivalent: "\u{F703}")
        focusRightItem.keyEquivalentModifierMask = [.command, .option]
        focusRightItem.target = self
        viewMenu.addItem(focusRightItem)

        let focusUpItem = NSMenuItem(title: "Focus Up Pane", action: #selector(focusUp), keyEquivalent: "\u{F700}")
        focusUpItem.keyEquivalentModifierMask = [.command, .option]
        focusUpItem.target = self
        viewMenu.addItem(focusUpItem)

        let focusDownItem = NSMenuItem(title: "Focus Down Pane", action: #selector(focusDown), keyEquivalent: "\u{F701}")
        focusDownItem.keyEquivalentModifierMask = [.command, .option]
        focusDownItem.target = self
        viewMenu.addItem(focusDownItem)

        viewMenu.addItem(.separator())

        let toggleZoomItem = NSMenuItem(title: "Toggle Pane Zoom", action: #selector(toggleZoom), keyEquivalent: "\r")
        toggleZoomItem.keyEquivalentModifierMask = [.command, .shift]
        toggleZoomItem.target = self
        viewMenu.addItem(toggleZoomItem)

        let canvasMenuItem = NSMenuItem(title: "Workflow Canvas", action: #selector(showWorkflowCanvas), keyEquivalent: "")
        canvasMenuItem.target = self
        viewMenu.addItem(canvasMenuItem)

        let viewMenuItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func newTab() {
        _ = paneManager?.createPane()
        // Route keyboard focus to the new surface; createPane alone leaves the
        // freshly added pane unfocused, so it would render but ignore input.
        paneManager?.focusCurrent()
    }

    @objc private func closeTab() {
        guard let current = paneManager?.currentPane else { return }
        closePaneOrWindow(current)
    }

    /// Close a pane, or the whole window when it is the last one. Removing the
    /// final pane would leave an empty window that accepts no input, so the last
    /// tab closes the window instead (which quits the app as the last window).
    private func closePaneOrWindow(_ pane: TerminalPane) {
        guard let manager = paneManager else { return }
        if manager.panes.count <= 1 {
            window?.performClose(nil)
        } else {
            manager.closePane(pane)
        }
    }

    @objc private func splitHorizontal() {
        paneManager?.splitHorizontal()
    }

    @objc private func splitVertical() {
        paneManager?.splitVertical()
    }

    @objc private func toggleSearch() {
        if searchOverlay.isVisible {
            searchOverlay.hide()
        } else if let pane = paneManager?.currentPane {
            searchOverlay.show(for: pane)
        }
    }

    @objc private func clearScrollback() {
        if let pane = paneManager?.currentPane {
            if let surface = pane.surface as? GhosttySurfaceController {
                surface.sendText("\u{1B}[3J")
            }
            pane.scrollbackBuffer.clear()
        }
    }

    @objc private func toggleSidebar() {
        showSidebar.toggle()
        sidebarHostingView?.isHidden = !showSidebar
        mainSplitView?.adjustSubviews()
        NSLog("symaira sidebar: \(showSidebar ? "shown" : "hidden")")
    }

    private func selectPaneByID(_ id: UUID) {
        guard let idx = paneManager?.panes.firstIndex(where: { $0.paneID == id }) else { return }
        paneManager?.selectPane(at: idx)
    }

    private func startMonitoring() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.updatePaneStatuses()
                guard let self else { break }
                let hasActive = await MainActor.run {
                    self.paneManager?.panes.contains { pane in
                        pane.agentStatus == .running || pane.agentStatus == .awaitingApproval
                    } ?? false
                }
                if !hasActive {
                    await MainActor.run { self.monitorTask = nil }
                    break
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func updatePaneStatuses() async {
        guard let manager = paneManager else { return }
        let parentMap = await workspaceMonitor.cachedProcessTree()
        let listeningPorts = await workspaceMonitor.cachedListeningPorts()

        var updatedItems: [PaneStatusInfo] = []
        let currentPanes = manager.panes

        for (index, pane) in currentPanes.enumerated() {
            let paneID = pane.paneID
            let title = oscEventHandler.title(for: paneID)
            let status = pane.agentStatus
            let isActive = (pane === manager.currentPane)

            let cwd = oscEventHandler.cwd(for: paneID)
                ?? pane.configuration.workingDirectory
                ?? URL(fileURLWithPath: NSHomeDirectory())

            let gitResult = await workspaceMonitor.cachedGitAndPRInfo(for: cwd, includePRInfo: isActive)

            let shellPID = pane.pid
            let panePorts = listeningPorts.filter { portInfo in
                WorkspaceMonitor.isDescendant(pid: portInfo.pid, parentPID: shellPID, parentMap: parentMap)
            }.map { $0.port }

            let info = PaneStatusInfo(
                id: paneID,
                index: index,
                title: title.isEmpty ? "Terminal" : title,
                status: status,
                isActive: isActive,
                cwd: cwd,
                gitBranch: gitResult.branch,
                gitIsDirty: gitResult.isDirty,
                gitAhead: gitResult.ahead,
                gitBehind: gitResult.behind,
                prNumber: gitResult.prNumber,
                prTitle: gitResult.prTitle,
                prStatus: gitResult.prStatus,
                listeningPorts: Array(Set(panePorts)).sorted()
            )
            updatedItems.append(info)
        }

        // Refresh worktree store dirty states
        if let store = sidebarViewModel?.worktreeStore {
            store.refreshDirtyState(for: store.worktrees)
        }

        await MainActor.run {
            self.sidebarViewModel?.paneItems = updatedItems
            self.checkActiveAgents()
        }
    }

    @objc private func togglePalette() {
        showPalette.toggle()
        if showPalette {
            showCommandPalette()
        }
    }

    @objc private func focusNext() {
        paneManager?.focusNext()
    }

    @objc private func focusPrevious() {
        paneManager?.focusPrevious()
    }

    @objc private func focusNextActive() {
        paneManager?.focusNextActive()
    }

    @objc private func focusPreviousActive() {
        paneManager?.focusPreviousActive()
    }

    @objc private func focusBlocked() {
        paneManager?.focusLongestBlocked()
    }

    @objc private func focusLeft() {
        paneManager?.focus(in: .left)
    }

    @objc private func focusRight() {
        paneManager?.focus(in: .right)
    }

    @objc private func focusUp() {
        paneManager?.focus(in: .up)
    }

    @objc private func focusDown() {
        paneManager?.focus(in: .down)
    }

    @objc private func toggleZoom() {
        paneManager?.toggleZoom()
    }

    @objc private func forkSession() {
        guard let currentPane = paneManager?.currentPane else { return }
        _ = paneManager?.forkSession(from: currentPane)
    }

    private func toggleDictation() {
        guard let currentPane = paneManager?.currentPane else { return }
        currentPane.inputEditor.toggleSTTRecording()
    }

    private func showSketchpad() {
        if let existing = sketchpadWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let sketchpadView = SketchpadView()
        let hostingController = NSHostingController(rootView: sketchpadView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 350),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sketchpad"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        sketchpadWindow = window
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

        let paletteView = CommandPalette(isPresented: .constant(true), items: items)
        let hostingController = NSHostingController(rootView: paletteView)
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 400, height: 320)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
            styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingController.view
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.title = "Command Palette"
        panel.isReleasedWhenClosed = false

        if let contentView = window.contentView {
            let rect = window.convertToScreen(NSRect(
                x: contentView.bounds.midX - 200,
                y: contentView.bounds.midY - 160,
                width: 400,
                height: 320
            ))
            panel.setFrameOrigin(rect.origin)
        }

        panel.orderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showSettings() {
        if let existing = settingsWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        var isPresented = true
        let settingsView = SettingsView(
            providerStore: providerStore,
            workspaceConfigManager: workspaceConfigManager,
            stackStore: stackStore,
            isPresented: Binding(
                get: { isPresented },
                set: { newValue in
                    isPresented = newValue
                    if !newValue {
                        self.settingsWindow?.close()
                    }
                }
            )
        )
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    private func showOnboarding() {
        var isPresented = true
        let onboardingView = OnboardingView(
            providerStore: providerStore,
            isPresented: Binding(
                get: { isPresented },
                set: { newValue in
                    isPresented = newValue
                    if !newValue {
                        self.onboardingWindow?.close()
                    }
                }
            )
        )
        let hostingController = NSHostingController(rootView: onboardingView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Symaira Terminal"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }

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

    @objc private func toggleKeepAwake() {
        let current = UserDefaults.standard.bool(forKey: "keepAwakeAlways")
        UserDefaults.standard.set(!current, forKey: "keepAwakeAlways")
        SleepPreventionManager.shared.updateAssertionState()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleKeepAwake) {
            menuItem.state = UserDefaults.standard.bool(forKey: "keepAwakeAlways") ? .on : .off
            return true
        }
        return true
    }

    private func checkActiveAgents() {
        guard let paneManager = self.paneManager else { return }
        let hasActive = paneManager.panes.contains { pane in
            pane.agentStatus == .running || pane.agentStatus == .awaitingApproval
        }
        SleepPreventionManager.shared.updateAgentActivityState(hasActiveAgent: hasActive)
        if hasActive && monitorTask == nil {
            startMonitoring()
        }
    }

    // MARK: - Workflow Canvas & Handoff Pipeline

    @objc private func showWorkflowCanvas() {
        workflowCoordinator.showWorkflowCanvas()
    }
}

extension AppDelegate: @preconcurrency TabBarDelegate {
    func tabBarDidSelectTab(_ tabBar: TabBarView, index: Int) {
        paneManager?.selectPane(at: index)
    }

    func tabBarDidRequestClose(_ tabBar: TabBarView, index: Int) {
        guard let paneManager, index < paneManager.panes.count else { return }
        closePaneOrWindow(paneManager.panes[index])
    }
}
