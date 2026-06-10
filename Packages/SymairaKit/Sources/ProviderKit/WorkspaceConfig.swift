import Foundation
import ProviderKit

public struct WorkspaceConfig: Codable, Equatable, Sendable {
    public var activeProfile: String
    public var profiles: [ProfileConfig]

    public struct ProfileConfig: Codable, Equatable, Sendable {
        public let name: String
        public var providerKeys: [ProviderID: String]

        public init(name: String, providerKeys: [ProviderID: String] = [:]) {
            self.name = name
            self.providerKeys = providerKeys
        }
    }

    public init(activeProfile: String = "default", profiles: [ProfileConfig] = []) {
        self.activeProfile = activeProfile
        self.profiles = profiles.isEmpty ? [ProfileConfig(name: "default")] : profiles
    }

    public static let `default` = WorkspaceConfig()

    public func profile(named name: String) -> ProfileConfig? {
        profiles.first { $0.name == name }
    }

    public func key(for provider: ProviderID) -> String? {
        profile(named: activeProfile)?.providerKeys[provider]
    }
}

public final class WorkspaceConfigManager: ObservableObject {
    @Published public var config: WorkspaceConfig

    private let configURL: URL

    public init(workspaceURL: URL) {
        self.configURL = workspaceURL.appendingPathComponent(".symaira/config.json")
        self.config = Self.load(from: configURL)
    }

    public func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: configURL, options: .atomic)
    }

    public func switchProfile(to name: String) {
        guard config.profiles.contains(where: { $0.name == name }) else { return }
        config.activeProfile = name
        save()
    }

    public func addProfile(_ name: String) {
        guard !config.profiles.contains(where: { $0.name == name }) else { return }
        config.profiles.append(WorkspaceConfig.ProfileConfig(name: name))
        save()
    }

    public func removeProfile(_ name: String) {
        guard name != "default", let index = config.profiles.firstIndex(where: { $0.name == name }) else { return }
        config.profiles.remove(at: index)
        if config.activeProfile == name {
            config.activeProfile = "default"
        }
        save()
    }

    private static func load(from url: URL) -> WorkspaceConfig {
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(WorkspaceConfig.self, from: data) else {
            return .default
        }
        return config
    }
}
