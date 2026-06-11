import Foundation
import ProviderKit

@MainActor
public final class ProviderStore: ObservableObject {
    @Published public var activeProfile: String = "default"
    @Published public var profiles: [String] = ["default"]
    @Published public var storedKeys: [ProviderID: String] = [:]

    private let keyStore: KeyStore
    private let configManager: WorkspaceConfigManager

    public init(keyStore: KeyStore = KeychainKeyStore(), configManager: WorkspaceConfigManager? = nil) {
        self.keyStore = keyStore
        self.configManager = configManager ?? WorkspaceConfigManager(workspaceURL: URL(fileURLWithPath: NSHomeDirectory()))
        syncFromConfig()
    }

    public func key(for provider: ProviderID) -> String? {
        storedKeys[provider]
    }

    public func hasKey(for provider: ProviderID) -> Bool {
        storedKeys[provider] != nil
    }

    public func setKey(_ key: String, for provider: ProviderID) throws {
        try keyStore.setKey(key, provider: provider, profile: activeProfile)
        storedKeys[provider] = key
    }

    public func deleteKey(for provider: ProviderID) {
        try? keyStore.deleteKey(provider: provider, profile: activeProfile)
        storedKeys[provider] = nil
    }

    public func loadKeys() {
        for provider in ProviderID.allCases {
            if let key = try? keyStore.key(provider: provider, profile: activeProfile) {
                storedKeys[provider] = key
            }
        }
    }

    public func switchProfile(to profile: String) {
        configManager.switchProfile(to: profile)
        syncFromConfig()
        storedKeys.removeAll()
        loadKeys()
    }

    public func addProfile(_ name: String) {
        configManager.addProfile(name)
        syncFromConfig()
    }

    public func removeProfile(_ name: String) {
        configManager.removeProfile(name)
        syncFromConfig()
    }

    private func syncFromConfig() {
        activeProfile = configManager.config.activeProfile
        profiles = configManager.config.profiles.map(\.name)
    }
}

extension ProviderID {
    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        case .openrouter: return "OpenRouter"
        case .google: return "Google"
        case .ollama: return "Ollama"
        case .openAICompatible: return "OpenAI Compatible"
        }
    }
}
