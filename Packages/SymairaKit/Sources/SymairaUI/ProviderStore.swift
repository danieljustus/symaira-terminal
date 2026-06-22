import Foundation
import ProviderKit

@MainActor
public final class ProviderStore: ObservableObject {
    @Published public var activeProfile: String = "default"
    @Published public var profiles: [String] = ["default"]
    @Published public var storedKeys: [ProviderID: String] = [:]
    @Published public var storedTokens: [ProviderID: OAuthToken] = [:]

    private let keyStore: KeyStore
    private let tokenStore: TokenStore
    private let configManager: WorkspaceConfigManager

    public init(
        keyStore: KeyStore = KeychainKeyStore(),
        tokenStore: TokenStore = KeychainTokenStore(),
        configManager: WorkspaceConfigManager? = nil
    ) {
        self.keyStore = keyStore
        self.tokenStore = tokenStore
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
            if let token = try? tokenStore.token(provider: provider, profile: activeProfile) {
                storedTokens[provider] = token
            }
        }
    }

    public func hasOAuthToken(for provider: ProviderID) -> Bool {
        storedTokens[provider] != nil
    }

    public func setOAuthToken(_ token: OAuthToken, for provider: ProviderID) throws {
        try tokenStore.setToken(token, provider: provider, profile: activeProfile)
        storedTokens[provider] = token
    }

    public func deleteOAuthToken(for provider: ProviderID) {
        try? tokenStore.deleteToken(provider: provider, profile: activeProfile)
        storedTokens[provider] = nil
    }

    public func signInWithOAuth(for provider: ProviderID) async throws {
        guard let config = provider.oauthConfig else {
            throw OAuthError.invalidURL("Provider does not support OAuth")
        }

        let authenticator = OAuthAuthenticator()
        let result = try await authenticator.authorize(config: config)

        guard let code = URLComponents(url: result.url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw OAuthError.noAccessToken
        }

        let tokenClient = OAuthTokenClient()
        let token = try await tokenClient.exchangeCode(code, config: config, codeVerifier: result.codeVerifier)
        try setOAuthToken(token, for: provider)
    }

    public func signOutOAuth(for provider: ProviderID) {
        deleteOAuthToken(for: provider)
    }

    public func switchProfile(to profile: String) throws {
        try configManager.switchProfile(to: profile)
        syncFromConfig()
        storedKeys.removeAll()
        storedTokens.removeAll()
        loadKeys()
    }

    public func addProfile(_ name: String) throws {
        try configManager.addProfile(name)
        syncFromConfig()
    }

    public func removeProfile(_ name: String) throws {
        try configManager.removeProfile(name)
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
