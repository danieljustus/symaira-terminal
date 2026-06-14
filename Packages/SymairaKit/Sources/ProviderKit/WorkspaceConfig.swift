import Foundation

public struct WorkspaceConfig: Codable, Equatable, Sendable {
    public var activeProfile: String
    public var profiles: [ProfileConfig]

    // MARK: - Agent Profiles (Strategic/YOLO + rules)

    /// Active agent profile name.
    public var activeAgentProfile: String
    /// All configured agent profiles for this workspace.
    public var agentProfiles: [AgentProfileConfig]

    public struct ProfileConfig: Codable, Equatable, Sendable {
        public let name: String
        public var baseURL: String?
        public var model: String?

        public init(name: String, baseURL: String? = nil, model: String? = nil) {
            self.name = name
            self.baseURL = baseURL
            self.model = model
        }
    }

    /// Lightweight agent profile config (Codable mirror of AgentKit.AgentProfile).
    public struct AgentProfileConfig: Codable, Equatable, Sendable, Identifiable {
        public var id: String { name }
        public let name: String
        public var mode: String  // "strategic" or "yolo"
        public var rules: [String]

        public init(name: String, mode: String = "strategic", rules: [String] = []) {
            self.name = name
            self.mode = mode
            self.rules = rules
        }
    }

    public init(
        activeProfile: String = "default",
        profiles: [ProfileConfig] = [],
        activeAgentProfile: String = "default",
        agentProfiles: [AgentProfileConfig] = []
    ) {
        self.activeProfile = activeProfile
        self.profiles = profiles.isEmpty ? [ProfileConfig(name: "default")] : profiles
        self.activeAgentProfile = activeAgentProfile
        self.agentProfiles = agentProfiles.isEmpty
            ? [AgentProfileConfig(name: "default")]
            : agentProfiles
    }

    public static let `default` = WorkspaceConfig()

    public func profile(named name: String) -> ProfileConfig? {
        profiles.first { $0.name == name }
    }

    public func agentProfile(named name: String) -> AgentProfileConfig? {
        agentProfiles.first { $0.name == name }
    }
}

public final class WorkspaceConfigManager: ObservableObject {
    @Published public var config: WorkspaceConfig

    private let configURL: URL

    public init(workspaceURL: URL) {
        self.configURL = workspaceURL.appendingPathComponent(".symaira/config.json")
        self.config = Self.load(from: configURL)
    }

    public func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: configURL, options: .atomic)
    }

    public func switchProfile(to name: String) throws {
        guard config.profiles.contains(where: { $0.name == name }) else { return }
        config.activeProfile = name
        try save()
    }

    public func addProfile(_ name: String) throws {
        guard !config.profiles.contains(where: { $0.name == name }) else { return }
        config.profiles.append(WorkspaceConfig.ProfileConfig(name: name))
        try save()
    }

    public func removeProfile(_ name: String) throws {
        guard name != "default", let index = config.profiles.firstIndex(where: { $0.name == name }) else { return }
        config.profiles.remove(at: index)
        if config.activeProfile == name {
            config.activeProfile = "default"
        }
        try save()
    }

    // MARK: - Agent Profile Management

    public func switchAgentProfile(to name: String) throws {
        guard config.agentProfiles.contains(where: { $0.name == name }) else { return }
        config.activeAgentProfile = name
        try save()
    }

    public func addAgentProfile(_ profile: WorkspaceConfig.AgentProfileConfig) throws {
        guard !config.agentProfiles.contains(where: { $0.name == profile.name }) else { return }
        config.agentProfiles.append(profile)
        try save()
    }

    public func updateAgentProfile(_ profile: WorkspaceConfig.AgentProfileConfig) throws {
        guard let index = config.agentProfiles.firstIndex(where: { $0.name == profile.name }) else { return }
        config.agentProfiles[index] = profile
        try save()
    }

    public func removeAgentProfile(_ name: String) throws {
        guard name != "default",
              let index = config.agentProfiles.firstIndex(where: { $0.name == name }) else { return }
        config.agentProfiles.remove(at: index)
        if config.activeAgentProfile == name {
            config.activeAgentProfile = "default"
        }
        try save()
    }

    private static func load(from url: URL) -> WorkspaceConfig {
        guard let data = try? Data(contentsOf: url) else {
            return .default
        }
        // Migration: strip providerKeys from any existing config file.
        // Keys must never be persisted — they live in the macOS Keychain only.
        guard var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .default
        }
        if var profiles = json["profiles"] as? [[String: Any]] {
            for i in profiles.indices {
                profiles[i].removeValue(forKey: "providerKeys")
            }
            json["profiles"] = profiles
        }
        guard let sanitizedData = try? JSONSerialization.data(withJSONObject: json),
              let config = try? JSONDecoder().decode(WorkspaceConfig.self, from: sanitizedData) else {
            return .default
        }
        return config
    }
}
