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
        // Google service-account credentials path — a pointer to a secret file
        // is just as sensitive as the secret itself.
        "GOOGLE_APPLICATION_CREDENTIALS",
        // GitHub tokens leak push/repo access into nested agents.
        "GH_TOKEN",
        "GITHUB_TOKEN"
    ]

    /// Variables whose name starts with any of these prefixes are stripped.
    public static let blockedPrefixes: [String] = [
        "ANTHROPIC_",
        "OPENAI_",
        "OPENROUTER_",
        "CLAUDE_CODE_",
        // Cover the whole AWS credential set, not just the secret key:
        // AWS_ACCESS_KEY_ID and AWS_SESSION_TOKEN are credentials too.
        "AWS_ACCESS_KEY",
        "AWS_SECRET",
        "AWS_SESSION_TOKEN",
        "AZURE_",
        "COHERE_",
        "HF_",
        "TOGETHER_",
        "HUGGINGFACE_",
        // Additional OpenAI-compatible provider key namespaces.
        "GROQ_",
        "MISTRAL_",
        "DEEPSEEK_",
        "XAI_"
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
