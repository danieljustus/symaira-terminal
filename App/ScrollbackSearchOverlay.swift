import AppKit
import GhosttyBridge
import TerminalCore

@MainActor
final class ScrollbackSearchOverlay: NSObject {
    private var panel: NSPanel?
    private var searchField: NSSearchField?
    private var matchLabel: NSTextField?
    private weak var targetPane: TerminalPane?
    private var matches: [SearchMatch] = []
    private var currentMatchIndex = 0
    private var debounceTimer: Timer?

    func show(for pane: TerminalPane) {
        targetPane = pane

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 52),
            styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.title = "Search Scrollback"
        panel.hidesOnDeactivate = false

        let searchField = NSSearchField(frame: NSRect(x: 0, y: 0, width: 280, height: 32))
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.target = self
        searchField.action = #selector(searchDidChange(_:))
        searchField.placeholderString = "Find in scrollback..."
        searchField.sendsSearchStringImmediately = true
        panel.contentView?.addSubview(searchField)

        let matchLabel = NSTextField(labelWithString: "")
        matchLabel.translatesAutoresizingMaskIntoConstraints = false
        matchLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        matchLabel.textColor = .secondaryLabelColor
        matchLabel.alignment = .right
        panel.contentView?.addSubview(matchLabel)

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor, constant: 12),
            searchField.centerYAnchor.constraint(equalTo: panel.contentView!.centerYAnchor),
            searchField.widthAnchor.constraint(equalToConstant: 280),

            matchLabel.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 8),
            matchLabel.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor, constant: -12),
            matchLabel.centerYAnchor.constraint(equalTo: panel.contentView!.centerYAnchor),
            matchLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 60)
        ])

        self.panel = panel
        self.searchField = searchField
        self.matchLabel = matchLabel

        if let window = pane.view.window {
            let rect = window.convertToScreen(NSRect(
                x: window.contentView!.bounds.midX - 180,
                y: window.contentView!.bounds.height - 60,
                width: 360,
                height: 52
            ))
            panel.setFrameOrigin(rect.origin)
        }

        panel.orderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        panel?.orderOut(nil)
        panel = nil
        searchField = nil
        matchLabel = nil
        targetPane = nil
        matches = []
        currentMatchIndex = 0
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    @objc private func searchDidChange(_ sender: NSSearchField) {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.performSearch(query: sender.stringValue)
            }
        }
    }

    private func performSearch(query: String) {
        guard !query.isEmpty, let pane = targetPane else {
            matches = []
            currentMatchIndex = 0
            updateMatchLabel()
            return
        }

        matches = pane.scrollbackBuffer.searchText(query)
        currentMatchIndex = matches.isEmpty ? 0 : 1
        updateMatchLabel()
    }

    private func updateMatchLabel() {
        if matches.isEmpty {
            matchLabel?.stringValue = searchField?.stringValue.isEmpty ?? true ? "" : "No matches"
        } else {
            matchLabel?.stringValue = "\(currentMatchIndex)/\(matches.count)"
        }
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
        guard !matches.isEmpty else { return }
        currentMatchIndex = ((currentMatchIndex - 1 + direction) % matches.count + matches.count) % matches.count + 1
        updateMatchLabel()
    }
}
