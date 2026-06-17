import Foundation

/// Identifies an AI agent or subscription provider that generates usage data.
public struct UsageProvider: Equatable, Hashable, Sendable, Codable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

/// Built-in provider registry — mirrors `AgentCatalog` IDs so callers can key by the same id.
public enum UsageProviders {
    public static let claudeCode  = UsageProvider(id: "claude-code", displayName: "Claude Code")
    public static let openCode    = UsageProvider(id: "opencode", displayName: "OpenCode")
    public static let geminiCLI   = UsageProvider(id: "gemini-cli", displayName: "Gemini CLI")
    public static let aider       = UsageProvider(id: "aider", displayName: "Aider")
    public static let codex       = UsageProvider(id: "codex", displayName: "OpenAI Codex CLI")
    public static let copilotCLI  = UsageProvider(id: "copilot-cli", displayName: "GitHub Copilot CLI")

    public static let all: [UsageProvider] = [
        claudeCode, openCode, geminiCLI, aider, codex, copilotCLI
    ]
}
