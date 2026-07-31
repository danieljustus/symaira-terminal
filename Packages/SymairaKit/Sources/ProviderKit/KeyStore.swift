import Foundation
import SymairaKeychain

/// AI providers supported by BYOK. `openAICompatible` covers any self-hosted or
/// third-party endpoint that speaks the OpenAI wire format (LM Studio, vLLM, …).
public enum ProviderID: String, CaseIterable, Sendable, Codable {
    case anthropic
    case openai
    case openrouter
    case google
    case ollama
    case openAICompatible = "openai-compatible"
}

extension ProviderID {
    /// The authentication methods architecturally supported by this provider.
    ///
    /// This is the **single source of truth** for auth modes. Both
    /// `ProviderSettingsView` and `OnboardingView` read this list to decide
    /// which credential UI to present. `ProviderChatClient` uses it to resolve
    /// the appropriate `ProviderCredential`.
    ///
    /// A provider may list multiple modes (e.g. `[.apiKey, .oauth(...)]`).
    /// The UI should present all supported options; `authMethod` picks the
    /// currently active one (respecting feature flags).
    public var supportedAuthModes: [AuthMethod] {
        switch self {
        case .anthropic, .openrouter, .ollama, .openAICompatible:
            return [.apiKey]
        case .openai:
            return [.apiKey, .oauth(.openAI)]
        case .google:
            return [.apiKey, .oauth(.google)]
        }
    }

    /// The currently active authentication method for this provider.
    ///
    /// Respects `OAuthFeature.isEnabled` — returns the first OAuth mode from
    /// `supportedAuthModes` when the flag is on, otherwise falls back to
    /// `.apiKey`. Prefer `supportedAuthModes` when building UI that should
    /// show all available options.
    public var authMethod: AuthMethod {
        for mode in supportedAuthModes {
            if case .oauth(let config) = mode, OAuthFeature.isEnabled {
                return .oauth(config)
            }
        }
        return .apiKey
    }

    /// Whether this provider supports OAuth sign-in (currently active).
    public var supportsOAuth: Bool {
        if case .oauth = authMethod { return true }
        return false
    }

    /// Whether this provider accepts a static API key.
    public var supportsAPIKey: Bool {
        supportedAuthModes.contains { mode in
            if case .apiKey = mode { return true }
            return false
        }
    }

    /// The OAuth configuration for this provider, if available.
    public var oauthConfig: OAuthConfig? {
        for mode in supportedAuthModes {
            if case .oauth(let config) = mode { return config }
        }
        return nil
    }

    /// Whether this provider has OAuth configuration defined, even when the
    /// feature flag is off. Used for "coming soon" hints in the UI.
    public var hasOAuthConfig: Bool {
        for mode in supportedAuthModes {
            if case .oauth = mode { return true }
        }
        return false
    }
}

public enum KeyStoreError: Error, Equatable {
    case keychainFailure(OSStatus)
}

/// Storage for BYOK API keys. Keys never touch config files, logs, or any
/// Symaira service — the implementation uses SymairaKeychain from symaira-appkit.
/// `profile` separates billing contexts (e.g. "private" vs "business") for
/// multi-account routing per workspace.
public protocol KeyStore: Sendable {
    func setKey(_ key: String, provider: ProviderID, profile: String) throws
    func key(provider: ProviderID, profile: String) throws -> String?
    func deleteKey(provider: ProviderID, profile: String) throws
}

extension KeyStore {
    static func account(provider: ProviderID, profile: String) -> String {
        "\(profile)/\(provider.rawValue)"
    }
}

/// SymairaKeychain-backed production store.
///
/// Uses `SymairaKeychain` (symaira-appkit) instead of direct Security framework
/// calls. Credentials stored under the legacy service names
/// (`com.symaira.terminal.byok` and `com.symaira.terminal.oauth`) are
/// migrated to the new namespace (`dev.symaira.symaira-terminal`) on first
/// access per profile so existing provider keys are not lost.
public struct KeychainKeyStore: KeyStore {
    /// Legacy service name for API keys — used during migration only.
    private static let legacyAPIKeyService = "com.symaira.terminal.byok"
    /// Legacy service name for OAuth tokens — used during migration only.
    private static let legacyOAuthService = "com.symaira.terminal.oauth"
    /// Sentinel key prefix for per-profile migration tracking.
    private static let migrationSentinelPrefix = "migration_done"

    /// Primary keychain for all current credential operations.
    private let keychain: SymairaKeychain
    /// Legacy keychain for reading old API-key entries during migration.
    private let legacyAPIKeychain: SymairaKeychain
    /// Legacy keychain for reading old OAuth-token entries during migration.
    private let legacyOAuthKeychain: SymairaKeychain

    public init() {
        keychain = SymairaKeychain(app: "symaira-terminal")
        legacyAPIKeychain = SymairaKeychain(service: Self.legacyAPIKeyService)
        legacyOAuthKeychain = SymairaKeychain(service: Self.legacyOAuthService)
    }

    // MARK: - Migration

    /// Migrate credentials for `profile` from the legacy service names on first
    /// access. The migration is idempotent — once a profile is migrated, the
    /// sentinel prevents redundant work.
    ///
    /// Migration path:
    /// 1. Read each `ProviderID` account from the legacy API-key keychain.
    /// 2. If found, save it under the new service and delete the legacy entry.
    /// 3. Repeat for the legacy OAuth-token keychain.
    /// 4. Write a sentinel so subsequent calls skip the work.
    private func migrateIfNeeded(profile: String) {
        let sentinelKey = "\(Self.migrationSentinelPrefix)/\(profile)"

        // Already migrated — sentinel exists.
        if (try? keychain.read(key: sentinelKey)) != nil { return }

        for provider in ProviderID.allCases {
            let account = Self.account(provider: provider, profile: profile)

            // API keys
            if let value = try? legacyAPIKeychain.read(key: account) {
                _ = try? keychain.save(value, key: account)
                legacyAPIKeychain.delete(key: account)
            }

            // OAuth tokens
            if let value = try? legacyOAuthKeychain.read(key: account) {
                _ = try? keychain.save(value, key: account)
                legacyOAuthKeychain.delete(key: account)
            }
        }

        // Mark migration complete for this profile.
        _ = try? keychain.save("1", key: sentinelKey)
    }

    // MARK: - KeyStore

    public func setKey(_ key: String, provider: ProviderID, profile: String) throws {
        migrateIfNeeded(profile: profile)
        let account = Self.account(provider: provider, profile: profile)
        try keychain.save(key, key: account)
    }

    public func key(provider: ProviderID, profile: String) throws -> String? {
        migrateIfNeeded(profile: profile)
        let account = Self.account(provider: provider, profile: profile)
        return try keychain.read(key: account)
    }

    public func deleteKey(provider: ProviderID, profile: String) throws {
        migrateIfNeeded(profile: profile)
        let account = Self.account(provider: provider, profile: profile)
        keychain.delete(key: account)
    }
}

/// Test/in-memory store — unit tests must never touch the real Keychain.
public final class InMemoryKeyStore: KeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String] = [:]

    public init() {}

    public func setKey(_ key: String, provider: ProviderID, profile: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[Self.account(provider: provider, profile: profile)] = key
    }

    public func key(provider: ProviderID, profile: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[Self.account(provider: provider, profile: profile)]
    }

    public func deleteKey(provider: ProviderID, profile: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[Self.account(provider: provider, profile: profile)] = nil
    }
}
