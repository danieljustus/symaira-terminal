import SymairaToolKit

// The tool registry moved to the shared symaira-appkit package
// (single source of truth for all Symaira clients). These typealiases
// keep StackKit's public API stable for existing consumers.
public typealias SymairaTool = SymairaToolKit.SymairaTool
public typealias SymairaToolRegistry = SymairaToolKit.SymairaToolRegistry

extension SymairaTool {
    /// MCP serve arguments with terminal-specific extras. The shared
    /// registry carries the neutral args; symvault additionally wants to
    /// know which agent is connecting.
    public var terminalMCPArgs: [String] {
        id == "symvault" ? mcpArgs + ["--agent", "symaira-terminal"] : mcpArgs
    }
}
