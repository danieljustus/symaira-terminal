import AppKit
import AgentKit
import TerminalCore

/// Where a `PaneManager.openTab` request originated. Drives the confirmation
/// dialog's wording so the user knows who is actually asking — an MCP-connected
/// AI agent and an arbitrary `symaira-terminal://` link are very different
/// levels of trust, even though both reach the same code path.
public enum OpenTabRequestOrigin {
    case mcp
    case urlScheme
}

extension PaneManager: TerminalMCPDelegate {
    public func getActiveScrollback(lines: Int) async -> String {
        guard let currentPane = self.currentPane else { return "" }
        if let text = currentPane.scrollbackBuffer.currentText {
            let linesArray = text.components(separatedBy: "\n")
            let suffixLines = linesArray.suffix(lines)
            return suffixLines.joined(separator: "\n")
        }
        return ""
    }

    public func openTab(command: String, workingDirectory: URL? = nil) async -> Bool {
        await openTab(command: command, workingDirectory: workingDirectory, origin: .mcp)
    }

    public func openTab(command: String, workingDirectory: URL?, origin: OpenTabRequestOrigin) async -> Bool {
        let alert = NSAlert()
        switch origin {
        case .mcp:
            alert.messageText = "AI Request: Open New Tab"
            alert.informativeText = "An AI agent is requesting to open a new terminal tab and execute the following command:\n\n\(command)\n\nDo you want to allow this?"
        case .urlScheme:
            alert.messageText = "External Link: Open New Tab"
            alert.informativeText = "A link — not an AI agent — is requesting to open a new terminal tab and execute the following command:\n\n\(command)\n\nOnly allow this if you trust where the link came from."
        }
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Deny")

        NSApp.activate(ignoringOtherApps: true)

        let response = alertRunner?(alert) ?? alert.runModal()
        if response == .alertFirstButtonReturn {
            if let workingDirectory {
                var config = TerminalSurfaceConfiguration(command: command)
                config.workingDirectory = workingDirectory
                _ = self.createPane(at: config)
            } else {
                _ = self.createPane(at: TerminalSurfaceConfiguration(command: command))
            }
            return true
        }
        return false
    }
}
