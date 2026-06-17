import Foundation

/// A CLI coding agent the terminal knows how to recognize and integrate.
public struct KnownAgent: Equatable, Sendable {
    public let id: String
    public let displayName: String
    /// Executable names as they appear in the process tree.
    public let executableNames: [String]
    /// Whether the agent speaks the Agent Client Protocol (JSON-RPC over stdio),
    /// enabling structured permission dialogs and tool-call timelines.
    public let supportsACP: Bool

    public init(id: String, displayName: String, executableNames: [String], supportsACP: Bool) {
        self.id = id
        self.displayName = displayName
        self.executableNames = executableNames
        self.supportsACP = supportsACP
    }
}

/// Built-in agent registry. The terminal stays agent-agnostic: anything not in
/// this list still runs fine in PTY mode — this only unlocks richer integration.
public enum AgentCatalog {
    public static let all: [KnownAgent] = [
        KnownAgent(id: "claude-code", displayName: "Claude Code", executableNames: ["claude"], supportsACP: false),
        KnownAgent(id: "opencode", displayName: "OpenCode", executableNames: ["opencode"], supportsACP: true),
        KnownAgent(id: "gemini-cli", displayName: "Gemini CLI", executableNames: ["gemini"], supportsACP: true),
        KnownAgent(id: "aider", displayName: "Aider", executableNames: ["aider"], supportsACP: false),
        KnownAgent(id: "codex", displayName: "OpenAI Codex CLI", executableNames: ["codex"], supportsACP: false),
        KnownAgent(id: "copilot-cli", displayName: "GitHub Copilot CLI", executableNames: ["copilot"], supportsACP: true)
    ]

    /// Matches a process executable name (basename, e.g. from the pane's
    /// foreground process) against the registry.
    public static func detect(processName: String) -> KnownAgent? {
        let basename = (processName as NSString).lastPathComponent
        return all.first { $0.executableNames.contains(basename) }
    }
}
