import AppKit
import AgentKit
import TerminalCore

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

    public func openTab(command: String) async -> Bool {
        let alert = NSAlert()
        alert.messageText = "AI Request: Open New Tab"
        alert.informativeText = "An AI agent is requesting to open a new terminal tab and execute the following command:\n\n\(command)\n\nDo you want to allow this?"
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Deny")

        NSApp.activate(ignoringOtherApps: true)

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            _ = self.createPane(at: TerminalSurfaceConfiguration(command: command))
            return true
        }
        return false
    }
}
