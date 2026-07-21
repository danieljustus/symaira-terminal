import AppKit

/// Builds and configures the application's main menu bar with keyboard
/// shortcuts. Extracted from `AppDelegate.setupKeyboardShortcuts` to
/// reduce the AppDelegate's line count.
///
/// Each `addMenuItem` call returns a configured `NSMenuItem` ready to
/// be added to the given menu. Actions still target the AppDelegate
/// (passed via `target`) because they are `@objc` methods on it.
@MainActor
enum AppMenuBuilder {

    struct MenuItemTarget {
        let target: AnyObject
        init(_ target: AnyObject) { self.target = target }
    }

    // MARK: - Public

    static func buildMainMenu(target: AnyObject) -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(makeAppMenu(target: target))
        mainMenu.addItem(makeFileMenu(target: target))
        mainMenu.addItem(makeViewMenu(target: target))
        return mainMenu
    }

    // MARK: - App Menu

    private static func makeAppMenu(target: AnyObject) -> NSMenuItem {
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(
            title: "About Symaira Terminal",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        ))
        appMenu.addItem(.separator())

        let keepAwakeItem = NSMenuItem(
            title: "Keep Mac Awake",
            action: Selector(("toggleKeepAwake")),
            keyEquivalent: ""
        )
        keepAwakeItem.target = target
        appMenu.addItem(keepAwakeItem)

        let settingsItem = NSMenuItem(
            title: "Settings\u{2026}",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ","
        )
        // Selector is set by the caller to avoid exposing @objc names in this file
        appMenu.addItem(settingsItem)

        appMenu.addItem(NSMenuItem(
            title: "Quit Symaira Terminal",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.submenu = appMenu
        return item
    }

    // MARK: - File Menu

    private static func makeFileMenu(target: AnyObject) -> NSMenuItem {
        let fileMenu = NSMenu(title: "File")

        fileMenu.addItem(makeMenuItem("New Tab", action: "newTab", key: "t", mask: [.command], target: target))
        fileMenu.addItem(makeMenuItem("New Workspace", action: "newTab", key: "n", mask: [.command], target: target))
        fileMenu.addItem(makeMenuItem("Close Tab", action: "closeTab", key: "w", mask: [.command], target: target))
        fileMenu.addItem(.separator())
        fileMenu.addItem(makeMenuItem("Split Horizontally", action: "splitHorizontal", key: "D", mask: [.command, .shift], target: target))
        fileMenu.addItem(makeMenuItem("Split Vertically", action: "splitVertical", key: "d", mask: [.command], target: target))
        fileMenu.addItem(.separator())
        fileMenu.addItem(makeMenuItem("Find in Scrollback", action: "toggleSearch", key: "f", mask: [.command], target: target))
        fileMenu.addItem(makeMenuItem("Clear Scrollback", action: "clearScrollback", key: "k", mask: [.command], target: target))

        let item = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        item.submenu = fileMenu
        return item
    }

    // MARK: - View Menu

    private static func makeViewMenu(target: AnyObject) -> NSMenuItem {
        let viewMenu = NSMenu(title: "View")

        viewMenu.addItem(makeMenuItem("Command Palette", action: "togglePalette", key: "p", mask: [.command, .shift], target: target))
        viewMenu.addItem(makeMenuItem("Toggle Sidebar", action: "toggleSidebar", key: "b", mask: [.command], target: target))
        viewMenu.addItem(.separator())
        viewMenu.addItem(makeMenuItem("Next Pane", action: "focusNext", key: "]", mask: [.command], target: target))
        viewMenu.addItem(makeMenuItem("Previous Pane", action: "focusPrevious", key: "[", mask: [.command], target: target))
        viewMenu.addItem(makeMenuItem("Focus Next Active Agent", action: "focusNextActive", key: "u", mask: [.command, .shift], target: target))
        viewMenu.addItem(makeMenuItem("Focus Previous Active Agent", action: "focusPreviousActive", key: "i", mask: [.command, .shift], target: target))
        viewMenu.addItem(.separator())
        viewMenu.addItem(makeMenuItem("Focus Left Pane", action: "focusLeft", key: "\u{F702}", mask: [.command, .option], target: target))
        viewMenu.addItem(makeMenuItem("Focus Right Pane", action: "focusRight", key: "\u{F703}", mask: [.command, .option], target: target))
        viewMenu.addItem(makeMenuItem("Focus Up Pane", action: "focusUp", key: "\u{F700}", mask: [.command, .option], target: target))
        viewMenu.addItem(makeMenuItem("Focus Down Pane", action: "focusDown", key: "\u{F701}", mask: [.command, .option], target: target))
        viewMenu.addItem(.separator())
        viewMenu.addItem(makeMenuItem("Toggle Pane Zoom", action: "toggleZoom", key: "\r", mask: [.command, .shift], target: target))
        viewMenu.addItem(makeMenuItem("Workflow Canvas", action: "showWorkflowCanvas", key: "", mask: [], target: target))

        let item = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        item.submenu = viewMenu
        return item
    }

    // MARK: - Helpers

    private static func makeMenuItem(
        _ title: String,
        action: String,
        key: String,
        mask: NSEvent.ModifierFlags,
        target: AnyObject
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: Selector(action), keyEquivalent: key)
        item.keyEquivalentModifierMask = mask
        item.target = target
        return item
    }
}
