import AppKit
import GhosttyBridge
import TerminalCore
import AgentKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var engine: GhosttyEngine?
    private var paneManager: PaneManager?
    private var oscEventHandler = OSCEventHandler()
    private var searchOverlay = ScrollbackSearchOverlay()
    private var tabBar: TabBarView?
    private var ghosttyConfig: GhosttyAppConfig?
    private var showSidebar = false
    private var showPalette = false
    private var sidebarItem: NSSplitViewItem?
    private var sidebarViewController: NSViewController?

    func applicationDidFinishLaunching(_: Notification) {
        let config = GhosttyAppConfig.parse()
        self.ghosttyConfig = config

        let engine = GhosttyEngine()
        self.engine = engine

        let manager = PaneManager(engine: engine)
        self.paneManager = manager

        manager.onPaneChanged = { [weak self] pane in
            self?.updateTitle(pane: pane)
            if let panes = self?.paneManager?.panes {
                self?.updateTabBar(panes: panes)
            }
        }
        manager.onPanesChanged = { [weak self] panes in
            self?.updateTabBar(panes: panes)
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

        contentView.addSubview(tabBar)
        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: contentView.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: 28),
        ])

        let paneContainer = NSView()
        paneContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(paneContainer)
        NSLayoutConstraint.activate([
            paneContainer.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            paneContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            paneContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            paneContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        manager.attach(to: paneContainer)
        tabBar.delegate = self

        setupKeyboardShortcuts(window: window)

        if let saved = SessionPersistence.shared.load() {
            restoreSession(saved, window: window, manager: manager)
        } else {
            _ = manager.createPane()
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_: Notification) {
        saveSession()
        paneManager?.panes.forEach { $0.close() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        saveSession()
        return .terminateNow
    }

    private func saveSession() {
        guard let manager = paneManager else { return }
        var state = manager.stateForPersistence
        if let window, let screen = window.screen {
            let frame = window.frame
            let screenFrame = screen.frame
            state.windowFrame = CodableRect(NSRect(
                x: frame.origin.x - screenFrame.origin.x,
                y: frame.origin.y - screenFrame.origin.y,
                width: frame.width,
                height: frame.height
            ))
        }
        try? SessionPersistence.shared.save(state)
    }

    private func restoreSession(_ state: SessionState, window: NSWindow, manager: PaneManager) {
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
            config.workingDirectory = paneState.workingDirectory.map(URL.init(fileURLWithPath:))
            config.environment = paneState.environment.isEmpty
                ? EnvironmentSanitizer.sanitizedProcessEnvironment()
                : paneState.environment
            _ = manager.createPane(at: config)
        }
    }

    // MARK: - Keyboard Shortcuts

    private func setupKeyboardShortcuts(window: NSWindow) {
        let mainMenu = window.menu ?? NSMenu()
        window.menu = mainMenu

        let fileMenu = NSMenu(title: "File")
        let newTabItem = NSMenuItem(title: "New Tab", action: #selector(newTab), keyEquivalent: "t")
        newTabItem.keyEquivalentModifierMask = [.command]
        newTabItem.target = self
        fileMenu.addItem(newTabItem)

        let closeTabItem = NSMenuItem(title: "Close Tab", action: #selector(closeTab), keyEquivalent: "w")
        closeTabItem.keyEquivalentModifierMask = [.command]
        closeTabItem.target = self
        fileMenu.addItem(closeTabItem)

        fileMenu.addItem(.separator())

        let splitHItem = NSMenuItem(title: "Split Horizontally", action: #selector(splitHorizontal), keyEquivalent: "d")
        splitHItem.keyEquivalentModifierMask = [.command]
        splitHItem.target = self
        fileMenu.addItem(splitHItem)

        let splitVItem = NSMenuItem(title: "Split Vertically", action: #selector(splitVertical), keyEquivalent: "D")
        splitVItem.keyEquivalentModifierMask = [.command, .shift]
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
        let sidebarItem = NSMenuItem(title: "Toggle Sidebar", action: #selector(toggleSidebar), keyEquivalent: "s")
        sidebarItem.keyEquivalentModifierMask = [.command, .control]
        sidebarItem.target = self
        viewMenu.addItem(sidebarItem)

        let paletteItem = NSMenuItem(title: "Command Palette", action: #selector(togglePalette), keyEquivalent: "p")
        paletteItem.keyEquivalentModifierMask = [.command, .shift]
        paletteItem.target = self
        viewMenu.addItem(paletteItem)

        viewMenu.addItem(.separator())

        let focusNextItem = NSMenuItem(title: "Next Pane", action: #selector(focusNext), keyEquivalent: "]")
        focusNextItem.keyEquivalentModifierMask = [.command]
        focusNextItem.target = self
        viewMenu.addItem(focusNextItem)

        let focusPrevItem = NSMenuItem(title: "Previous Pane", action: #selector(focusPrevious), keyEquivalent: "[")
        focusPrevItem.keyEquivalentModifierMask = [.command]
        focusPrevItem.target = self
        viewMenu.addItem(focusPrevItem)

        let focusBlockedItem = NSMenuItem(title: "Focus Blocked Agent", action: #selector(focusBlocked), keyEquivalent: "u")
        focusBlockedItem.keyEquivalentModifierMask = [.command, .shift]
        focusBlockedItem.target = self
        viewMenu.addItem(focusBlockedItem)

        let viewMenuItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)
    }

    @objc private func newTab() {
        _ = paneManager?.createPane()
    }

    @objc private func closeTab() {
        if let current = paneManager?.currentPane {
            paneManager?.closePane(current)
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
        if let surface = paneManager?.currentPane?.surface as? GhosttySurfaceController {
            surface.sendText("\u{1B}[3J")
        }
    }

    @objc private func toggleSidebar() {
        showSidebar.toggle()
        NSLog("symaira sidebar: \(showSidebar ? "shown" : "hidden")")
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

    @objc private func focusBlocked() {
        paneManager?.focusLongestBlocked()
    }

    private func showCommandPalette() {
        guard let window else { return }
        let items = [
            CommandPaletteItem(name: "New Tab", shortcut: "⌘T", category: "Tabs") { [weak self] in self?.newTab() },
            CommandPaletteItem(name: "Close Tab", shortcut: "⌘W", category: "Tabs") { [weak self] in self?.closeTab() },
            CommandPaletteItem(name: "Split Horizontally", shortcut: "⌘D", category: "Splits") { [weak self] in self?.splitHorizontal() },
            CommandPaletteItem(name: "Split Vertically", shortcut: "⌘⇧D", category: "Splits") { [weak self] in self?.splitVertical() },
            CommandPaletteItem(name: "Find in Scrollback", shortcut: "⌘F", category: "Navigation") { [weak self] in self?.toggleSearch() },
            CommandPaletteItem(name: "Clear Scrollback", shortcut: "⌘K", category: "Navigation") { [weak self] in self?.clearScrollback() },
            CommandPaletteItem(name: "Next Pane", shortcut: "⌘]", category: "Navigation") { [weak self] in self?.focusNext() },
            CommandPaletteItem(name: "Previous Pane", shortcut: "⌘[", category: "Navigation") { [weak self] in self?.focusPrevious() },
            CommandPaletteItem(name: "Focus Blocked Agent", shortcut: "⌘⇧U", category: "Navigation") { [weak self] in self?.focusBlocked() },
            CommandPaletteItem(name: "Toggle Sidebar", shortcut: "⌘⌃S", category: "View") { [weak self] in self?.toggleSidebar() },
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

    private func updateTitle(pane: TerminalPane?) {
        guard let pane else { return }
        let title = oscEventHandler.title(for: pane.paneID)
        window?.title = "\(title) — Symaira Terminal"
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
    }
}

extension AppDelegate: @preconcurrency TabBarDelegate {
    func tabBarDidSelectTab(_ tabBar: TabBarView, index: Int) {
        paneManager?.selectPane(at: index)
    }

    func tabBarDidRequestClose(_ tabBar: TabBarView, index: Int) {
        guard let paneManager, index < paneManager.panes.count else { return }
        let pane = paneManager.panes[index]
        paneManager.closePane(pane)
    }
}

import SwiftUI
