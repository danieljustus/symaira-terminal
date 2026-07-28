import AppKit

/// Builds and configures the application's main menu bar with keyboard
/// shortcuts. Extracted from `AppDelegate.setupKeyboardShortcuts` to
/// reduce the AppDelegate's line count.
///
/// File and View menus are registry-driven via `AppCommandRegistry` so
/// names, shortcuts, and modifier ordering stay consistent between the
/// menu bar and the Command Palette. App, Edit, Window, and Help menus
/// contain standard macOS items with fixed selectors.
@MainActor
enum AppMenuBuilder {

    // MARK: - Public

    static func buildMainMenu(target: AnyObject) -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(makeAppMenu(target: target))
        mainMenu.addItem(makeFileMenu(target: target))
        mainMenu.addItem(makeEditMenu(target: target))
        mainMenu.addItem(makeViewMenu(target: target))
        mainMenu.addItem(makeWindowMenu(target: target))
        mainMenu.addItem(makeHelpMenu(target: target))
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

        let settingsItem = NSMenuItem(
            title: "Settings\u{2026}",
            action: Selector(("showSettings")),
            keyEquivalent: ","
        )
        settingsItem.target = target
        appMenu.addItem(settingsItem)

        appMenu.addItem(.separator())

        appMenu.addItem(NSMenuItem(
            title: "Services",
            action: nil,
            keyEquivalent: ""
        ))
        NSApp.servicesMenu = appMenu.item(withTitle: "Services")?.submenu ?? NSMenu()

        appMenu.addItem(.separator())

        let hideItem = NSMenuItem(
            title: "Hide Symaira Terminal",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        appMenu.addItem(hideItem)

        appMenu.addItem(NSMenuItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        ).withModifierMask([.command, .option]))

        appMenu.addItem(NSMenuItem(
            title: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
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

        let checkForUpdatesItem = NSMenuItem(
            title: "Check for Updates\u{2026}",
            action: Selector(("checkForUpdates")),
            keyEquivalent: ""
        )
        checkForUpdatesItem.target = target
        appMenu.addItem(checkForUpdatesItem)

        appMenu.addItem(.separator())

        appMenu.addItem(NSMenuItem(
            title: "Quit Symaira Terminal",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.submenu = appMenu
        return item
    }

    // MARK: - File Menu (registry-driven)

    private static func makeFileMenu(target: AnyObject) -> NSMenuItem {
        let fileMenu = NSMenu(title: "File")
        let commands = AppCommandRegistry.commandsByMenu[.file, default: []]

        for cmd in commands {
            if cmd.separatorBefore { fileMenu.addItem(.separator()) }
            fileMenu.addItem(AppCommandRegistry.makeMenuItem(from: cmd, target: target))
        }

        let item = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        item.submenu = fileMenu
        return item
    }

    // MARK: - Edit Menu

    private static func makeEditMenu(target: AnyObject) -> NSMenuItem {
        let editMenu = NSMenu(title: "Edit")

        editMenu.addItem(NSMenuItem(
            title: "Undo",
            action: Selector(("undo:")),
            keyEquivalent: "z"
        ))
        editMenu.addItem(NSMenuItem(
            title: "Redo",
            action: Selector(("redo:")),
            keyEquivalent: "Z"
        ).withModifierMask([.command, .shift]))

        editMenu.addItem(.separator())

        editMenu.addItem(NSMenuItem(
            title: "Cut",
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        ))
        editMenu.addItem(NSMenuItem(
            title: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        ))
        editMenu.addItem(NSMenuItem(
            title: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        ))
        editMenu.addItem(NSMenuItem(
            title: "Paste Selection",
            action: Selector(("pasteSelection:")),
            keyEquivalent: "V"
        ).withModifierMask([.command, .shift]))
        editMenu.addItem(NSMenuItem(
            title: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        ))

        editMenu.addItem(.separator())

        editMenu.addItem(makeMenuItem("Find in Scrollback", action: "toggleSearch", key: "f", mask: [.command], target: target))
        editMenu.addItem(makeMenuItem("Clear Scrollback", action: "clearScrollback", key: "k", mask: [.command], target: target))

        editMenu.addItem(.separator())

        editMenu.addItem(NSMenuItem(
            title: "Emoji & Symbols",
            action: #selector(NSApplication.orderFrontCharacterPalette(_:)),
            keyEquivalent: " "
        ).withModifierMask([.command, .control]))

        let item = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        item.submenu = editMenu
        return item
    }

    // MARK: - View Menu (registry-driven)

    private static func makeViewMenu(target: AnyObject) -> NSMenuItem {
        let viewMenu = NSMenu(title: "View")
        let commands = AppCommandRegistry.commandsByMenu[.view, default: []]

        for cmd in commands {
            if cmd.separatorBefore { viewMenu.addItem(.separator()) }
            viewMenu.addItem(AppCommandRegistry.makeMenuItem(from: cmd, target: target))
        }

        let item = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        item.submenu = viewMenu
        return item
    }

    // MARK: - Window Menu

    private static func makeWindowMenu(target: AnyObject) -> NSMenuItem {
        let windowMenu = NSMenu(title: "Window")

        windowMenu.addItem(NSMenuItem(
            title: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        ))
        windowMenu.addItem(NSMenuItem(
            title: "Zoom",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        ))

        windowMenu.addItem(.separator())

        windowMenu.addItem(NSMenuItem(
            title: "Bring All to Front",
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        ))

        let item = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        item.submenu = windowMenu
        return item
    }

    // MARK: - Help Menu

    private static func makeHelpMenu(target: AnyObject) -> NSMenuItem {
        let helpMenu = NSMenu(title: "Help")

        let docsItem = NSMenuItem(
            title: "Symaira Terminal Help",
            action: Selector(("openHelpDocumentation")),
            keyEquivalent: "?"
        )
        docsItem.target = target
        helpMenu.addItem(docsItem)

        let item = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        item.submenu = helpMenu
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

// MARK: - NSMenuItem Modifier Mask Helper

private extension NSMenuItem {
    func withModifierMask(_ mask: NSEvent.ModifierFlags) -> NSMenuItem {
        keyEquivalentModifierMask = mask
        return self
    }
}
