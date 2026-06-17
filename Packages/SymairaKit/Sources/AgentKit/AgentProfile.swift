import Foundation

/// Agent operating mode — controls how much autonomy the agent has.
public enum AgentMode: String, Codable, CaseIterable, Sendable {
    /// Agent plans, asks permission before every shell command, works defensively.
    case strategic
    /// Agent has full write/execute permissions and reports only when all tests pass.
    case yolo

    public var displayName: String {
        switch self {
        case .strategic: "Strategic"
        case .yolo: "YOLO"
        }
    }

    public var description: String {
        switch self {
        case .strategic:
            "Agent asks before running commands. Safe for production and critical code."
        case .yolo:
            "Agent has full autonomy. Reports only when all tests pass."
        }
    }
}

/// Per-workspace agent profile with operating mode and custom rules.
public struct AgentProfile: Codable, Equatable, Sendable, Identifiable {
    public var id: String { name }

    /// Profile name (unique within workspace).
    public let name: String
    /// Operating mode.
    public var mode: AgentMode
    /// Project-wide tech-stack rules injected into every agent session.
    public var rules: [String]

    public init(
        name: String,
        mode: AgentMode = .strategic,
        rules: [String] = []
    ) {
        self.name = name
        self.mode = mode
        self.rules = rules
    }

    /// Built-in default profile.
    public static let `default` = AgentProfile(name: "default")

    /// Common rules users might want as templates.
    public static let suggestedRules = [
        "Use pnpm instead of npm",
        "UI only with Tailwind v4",
        "Never commit .env files",
        "Run tests before pushing",
        "Use conventional commits"
    ]
}
