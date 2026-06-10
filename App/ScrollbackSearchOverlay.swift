import AppKit
import GhosttyBridge
import TerminalCore

@MainActor
final class ScrollbackSearchOverlay: NSObject {
    private var panel: NSPanel?
    private var searchField: NSSearchField?
    private weak var targetSurface: (any TerminalSurface)?
    private var matchCount = 0
    private var currentMatch = 0

    func show(for surface: any TerminalSurface) {
        targetSurface = surface

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 52),
            styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.title = "Search Scrollback"
        panel.hidesOnDeactivate = false

        let searchField = NSSearchField(frame: panel.contentView!.bounds)
        searchField.autoresizingMask = [.width, .height]
        searchField.target = self
        searchField.action = #selector(searchDidChange(_:))
        searchField.placeholderString = "Find in scrollback..."
        searchField.sendsSearchStringImmediately = true
        panel.contentView?.addSubview(searchField)
        panel.initialFirstResponder = searchField

        self.panel = panel
        self.searchField = searchField

        if let window = surface.view.window {
            let rect = window.convertToScreen(NSRect(x: window.contentView!.bounds.midX - 160, y: window.contentView!.bounds.height - 60, width: 320, height: 52))
            panel.setFrameOrigin(rect.origin)
        }

        panel.orderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        searchField = nil
        targetSurface = nil
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    @objc private func searchDidChange(_ sender: NSSearchField) {
        let query = sender.stringValue
        guard !query.isEmpty else {
            matchCount = 0
            currentMatch = 0
            return
        }
        guard let surface = targetSurface as? GhosttySurfaceController,
              let viewportText = surface.readViewportText()
        else { return }

        let matches = viewportText.lowercased().components(separatedBy: query.lowercased()).count - 1
        matchCount = max(0, matches)
        currentMatch = matchCount > 0 ? 1 : 0
    }

    func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        let key = event.charactersIgnoringModifiers ?? ""
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if key == "\u{1B}" && mods.isEmpty {
            hide()
            return true
        }
        if key == "g" && mods.contains(.command) {
            cycleMatch(direction: event.modifierFlags.contains(.shift) ? -1 : 1)
            return true
        }
        return false
    }

    private func cycleMatch(direction: Int) {
        guard matchCount > 0 else { return }
        currentMatch = ((currentMatch - 1 + direction) % matchCount + matchCount) % matchCount + 1
    }
}
