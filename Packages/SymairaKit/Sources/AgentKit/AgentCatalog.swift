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

    /// Looks up a known agent by its identifier string (e.g. "claude-code").
    /// Returns `nil` for unrecognized IDs.
    public static func lookup(id: String) -> KnownAgent? {
        all.first { $0.id == id }
    }

    /// Resolves the full filesystem path for an executable name by searching
    /// the user's `PATH` environment variable. Returns `nil` if the executable
    /// cannot be found or is not executable.
    public static func resolveExecutablePath(named name: String) -> String? {
        // Absolute paths are used as-is if the file exists and is executable.
        if name.hasPrefix("/") {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: name, isDirectory: &isDir),
                  !isDir.boolValue,
                  FileManager.default.isExecutableFile(atPath: name) else {
                return nil
            }
            return name
        }

        // Search PATH directories.
        guard let pathEnv = ProcessInfo.processInfo.environment["PATH"] else { return nil }
        for dir in pathEnv.split(separator: ":") {
            let fullPath = "\(dir)/\(name)"
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir),
                  !isDir.boolValue else {
                continue
            }
            if FileManager.default.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }
        return nil
    }
}
