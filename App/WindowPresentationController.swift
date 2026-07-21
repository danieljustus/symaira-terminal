import AppKit
import SwiftUI
import ProviderKit
import StackKit
import SymairaUI

/// Manages the auxiliary windows: Settings, Onboarding, Sketchpad, and
/// Command Palette. Extracted from `AppDelegate` to reduce its line count.
@MainActor
final class WindowPresentationController {
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var sketchpadWindow: NSWindow?
    private let providerStore: ProviderStore
    private let workspaceConfigManager: WorkspaceConfigManager
    private let stackStore: StackStore

    init(
        providerStore: ProviderStore,
        workspaceConfigManager: WorkspaceConfigManager,
        stackStore: StackStore
    ) {
        self.providerStore = providerStore
        self.workspaceConfigManager = workspaceConfigManager
        self.stackStore = stackStore
    }

    // MARK: - Settings

    func showSettings() {
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
                set: { [weak self] newValue in
                    isPresented = newValue
                    if !newValue { self?.settingsWindow?.close() }
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

    // MARK: - Onboarding

    func showOnboarding() {
        var isPresented = true
        let onboardingView = OnboardingView(
            providerStore: providerStore,
            isPresented: Binding(
                get: { isPresented },
                set: { [weak self] newValue in
                    isPresented = newValue
                    if !newValue { self?.onboardingWindow?.close() }
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

    // MARK: - Sketchpad

    func showSketchpad() {
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

    // MARK: - Command Palette

    func showCommandPalette(
        window: NSWindow,
        actions: [CommandPaletteItem]
    ) {
        let paletteView = CommandPalette(isPresented: .constant(true), items: actions)
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
}
