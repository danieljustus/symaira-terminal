import Foundation

/// Protocol implemented by the terminal app's PaneManager to handle MCP tool execution.
public protocol TerminalMCPDelegate: AnyObject, Sendable {
    func getActiveScrollback(lines: Int) async -> String
    func openTab(command: String) async -> Bool
}
