import Foundation

/// Strips provider secrets and agent control flags from child-process
/// environments. Nested agent sessions (e.g. spawning `claude` from inside a
/// running Claude Code session) must not silently inherit API keys or flags —
/// that causes recursive invocation loops and silent billing surprises.
///
/// Workspace profiles re-inject the keys they explicitly route to a session.
public enum EnvironmentSanitizer {
    /// Exact variable names that never pass through to spawned agent processes.
    public static let blockedNames: Set<String> = [
        "CLAUDECODE",
        "GOOGLE_API_KEY",
        "GEMINI_API_KEY",
    ]

    /// Variables whose name starts with any of these prefixes are stripped.
    public static let blockedPrefixes: [String] = [
        "ANTHROPIC_",
        "OPENAI_",
        "OPENROUTER_",
        "CLAUDE_CODE_",
    ]

    public static func sanitize(_ environment: [String: String]) -> [String: String] {
        environment.filter { name, _ in
            !blockedNames.contains(name)
                && !blockedPrefixes.contains(where: name.hasPrefix)
        }
    }

    /// Sanitized copy of the current process environment — the baseline for
    /// every PTY/agent session the app spawns.
    public static func sanitizedProcessEnvironment() -> [String: String] {
        sanitize(ProcessInfo.processInfo.environment)
    }
}
