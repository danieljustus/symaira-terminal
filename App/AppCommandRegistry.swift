import AppKit

/// Shared command registry — single source of truth for menu items and the
/// Command Palette.  Both `AppMenuBuilder` and the palette in `AppDelegate`
/// read from this registry so names, shortcuts, and modifier ordering stay
/// consistent everywhere.
///
/// Modifier glyphs are rendered in NSEvent-style order: ⌃ ⌥ ⇧ ⌘.
@MainActor
enum AppCommandRegistry {

    // MARK: - Command definition

    enum MenuGroup: String {
        case file
        case view
        case app
        case none
    }

    struct Command: Identifiable {
        let id: String
        let title: String
        let action: String
        let key: String
        let modifiers: NSEvent.ModifierFlags
        let category: String
        let menuGroup: MenuGroup
        let separatorBefore: Bool

        // Palette shortcut string in correct NSEvent glyph order.
        var paletteShortcut: String? {
            guard !key.isEmpty, modifiers != [] || key == "\r" else {
                // No key means no shortcut glyph in the palette.
                return key.isEmpty ? nil : nil
            }
            if key.isEmpty && modifiers.isEmpty { return nil }
            let glyphs = modifiers.shortcutGlyphs
            let keyGlyph = Self.keyGlyph(for: key)
            return "\(glyphs)\(keyGlyph)"
        }
    }

    // MARK: - All commands

    static let all: [Command] = [
        // ── File ──────────────────────────────────────────
        Command(id: "new-tab",
                title: "New Tab",
                action: "newTab",
                key: "t", modifiers: .command,
                category: "Tabs", menuGroup: .file,
                separatorBefore: false),
        Command(id: "new-workspace",
                title: "New Workspace",
                action: "newTab",
                key: "n", modifiers: .command,
                category: "Tabs", menuGroup: .file,
                separatorBefore: false),
        Command(id: "close-tab",
                title: "Close Tab",
                action: "closeTab",
                key: "w", modifiers: .command,
                category: "Tabs", menuGroup: .file,
                separatorBefore: false),
        Command(id: "split-horizontal",
                title: "Split Horizontally",
                action: "splitHorizontal",
                key: "D", modifiers: [.command, .shift],
                category: "Splits", menuGroup: .file,
                separatorBefore: true),
        Command(id: "split-vertical",
                title: "Split Vertically",
                action: "splitVertical",
                key: "d", modifiers: .command,
                category: "Splits", menuGroup: .file,
                separatorBefore: false),
        Command(id: "fork-session",
                title: "Fork Session",
                action: "forkSession",
                key: "F", modifiers: [.command, .shift],
                category: "Session", menuGroup: .file,
                separatorBefore: true),
        Command(id: "find-scrollback",
                title: "Find in Scrollback",
                action: "toggleSearch",
                key: "f", modifiers: .command,
                category: "Navigation", menuGroup: .none,
                separatorBefore: true),
        Command(id: "clear-scrollback",
                title: "Clear Scrollback",
                action: "clearScrollback",
                key: "k", modifiers: .command,
                category: "Navigation", menuGroup: .none,
                separatorBefore: false),

        // ── View ──────────────────────────────────────────
        Command(id: "command-palette",
                title: "Command Palette",
                action: "togglePalette",
                key: "p", modifiers: [.command, .shift],
                category: "View", menuGroup: .view,
                separatorBefore: false),
        Command(id: "toggle-sidebar",
                title: "Toggle Sidebar",
                action: "toggleSidebar",
                key: "b", modifiers: .command,
                category: "View", menuGroup: .view,
                separatorBefore: false),
        Command(id: "next-pane",
                title: "Next Pane",
                action: "focusNext",
                key: "]", modifiers: .command,
                category: "Navigation", menuGroup: .view,
                separatorBefore: true),
        Command(id: "previous-pane",
                title: "Previous Pane",
                action: "focusPrevious",
                key: "[", modifiers: .command,
                category: "Navigation", menuGroup: .view,
                separatorBefore: false),
        Command(id: "focus-next-active-agent",
                title: "Focus Next Active Agent",
                action: "focusNextActive",
                key: "u", modifiers: [.command, .shift],
                category: "Navigation", menuGroup: .view,
                separatorBefore: false),
        Command(id: "focus-previous-active-agent",
                title: "Focus Previous Active Agent",
                action: "focusPreviousActive",
                key: "i", modifiers: [.command, .shift],
                category: "Navigation", menuGroup: .view,
                separatorBefore: false),
        Command(id: "focus-left",
                title: "Focus Left Pane",
                action: "focusLeft",
                key: String(UnicodeScalar(NSLeftArrowFunctionKey)!),
                modifiers: [.command, .option],
                category: "Navigation", menuGroup: .view,
                separatorBefore: true),
        Command(id: "focus-right",
                title: "Focus Right Pane",
                action: "focusRight",
                key: String(UnicodeScalar(NSRightArrowFunctionKey)!),
                modifiers: [.command, .option],
                category: "Navigation", menuGroup: .view,
                separatorBefore: false),
        Command(id: "focus-up",
                title: "Focus Up Pane",
                action: "focusUp",
                key: String(UnicodeScalar(NSUpArrowFunctionKey)!),
                modifiers: [.command, .option],
                category: "Navigation", menuGroup: .view,
                separatorBefore: false),
        Command(id: "focus-down",
                title: "Focus Down Pane",
                action: "focusDown",
                key: String(UnicodeScalar(NSDownArrowFunctionKey)!),
                modifiers: [.command, .option],
                category: "Navigation", menuGroup: .view,
                separatorBefore: false),
        Command(id: "toggle-pane-zoom",
                title: "Toggle Pane Zoom",
                action: "toggleZoom",
                key: "\r", modifiers: [.command, .shift],
                category: "Navigation", menuGroup: .view,
                separatorBefore: true),
        Command(id: "focus-blocked-agent",
                title: "Focus Blocked Agent",
                action: "focusBlocked",
                key: "j", modifiers: [.command, .shift, .option],
                category: "Navigation", menuGroup: .view,
                separatorBefore: false),
        Command(id: "toggle-dictation",
                title: "Toggle Dictation",
                action: "toggleDictation",
                key: "", modifiers: [],
                category: "Input", menuGroup: .view,
                separatorBefore: true),
        Command(id: "open-sketchpad",
                title: "Open Sketchpad",
                action: "showSketchpad",
                key: "", modifiers: [],
                category: "Input", menuGroup: .view,
                separatorBefore: false),
        Command(id: "workflow-canvas",
                title: "Workflow Canvas",
                action: "showWorkflowCanvas",
                key: "", modifiers: [],
                category: "Workflow", menuGroup: .view,
                separatorBefore: false),
    ]

    // MARK: - Menu helpers

    /// Commands grouped by their `menuGroup`, in insertion order.
    static var commandsByMenu: [MenuGroup: [Command]] {
        Dictionary(grouping: all, by: \.menuGroup)
    }

    /// Build an `NSMenuItem` from a command, targeting the given object.
    static func makeMenuItem(from command: Command, target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(
            title: command.title,
            action: Selector(command.action),
            keyEquivalent: command.key
        )
        item.keyEquivalentModifierMask = command.modifiers
        item.target = target
        return item
    }

    /// Palette items in the canonical insertion order.
    static func paletteItems(target: AnyObject) -> [CommandPaletteItem] {
        all.compactMap { cmd in
            // When the receiver conforms to a protocol or we cast to AppDelegate
            // the weak capture inside the closure has to go through `target`.
            guard target.responds(to: Selector(cmd.action)) else {
                // Skip commands whose action isn't implemented on the target —
                // this guards against stale registry entries.
                return nil
            }
            return CommandPaletteItem(
                name: cmd.title,
                shortcut: cmd.paletteShortcut,
                category: cmd.category
            ) { [weak target] in
                _ = target?.perform(Selector(cmd.action))
            }
        }
    }

    // MARK: - Key glyphs

    /// Maps a keyEquivalent string to its display glyph for the palette.
    /// Returns the key as-is for characters that don't have a special glyph.
    private static func keyGlyph(for key: String) -> String {
        switch key {
        case "\r":       return "↩"
        case "\u{7F}":   return "⌫"   // backspace
        case "\u{F728}": return "⌦"   // forward delete
        case "\u{0009}": return "⇥"   // tab
        case "\u{001B}": return "⎋"   // escape
        case "\u{0020}": return "␣"   // space
        default:
            // Arrow keys sent as NSEvent function-key scalars
            if let code = key.unicodeScalars.first?.value {
                switch code {
                case UInt32(NSLeftArrowFunctionKey):  return "←"
                case UInt32(NSRightArrowFunctionKey): return "→"
                case UInt32(NSUpArrowFunctionKey):    return "↑"
                case UInt32(NSDownArrowFunctionKey):  return "↓"
                default: break
                }
            }
            // Uppercase the key for display (menus show uppercase for letter keys).
            // For non-letter characters like "[" / "]" / "," we return as-is.
            if key.count == 1, key.rangeOfCharacter(from: .letters) != nil {
                return key.uppercased()
            }
            return key
        }
    }
}

// MARK: - Modifier glyph formatting (NSEvent order: ⌃ ⌥ ⇧ ⌘)

extension NSEvent.ModifierFlags {
    /// Glyphs for each modifier flag in the canonical NSEvent order (⌃ ⌥ ⇧ ⌘).
    var shortcutGlyphs: String {
        var result = ""
        if contains(.control) { result += "\u{2303}" }   // ⌃
        if contains(.option)  { result += "\u{2325}" }   // ⌥
        if contains(.shift)   { result += "\u{21E7}" }   // ⇧
        if contains(.command) { result += "\u{2318}" }   // ⌘
        return result
    }
}
