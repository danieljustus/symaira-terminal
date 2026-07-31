import Foundation
import SymairaKeychain

/// Storage for OAuth tokens. Tokens live in the macOS Keychain only — never
/// in config files, logs, or any Symaira service. Uses SymairaKeychain from
/// symaira-appkit instead of direct Security framework calls.
///
/// Migration: On first access per profile, existing OAuth tokens stored under
/// the legacy service name `com.symaira.terminal.oauth` are read, migrated to
/// the new service (`dev.symaira.symaira-terminal`), and removed from the
/// legacy store. API-key migration is handled by `KeychainKeyStore`; both
/// stores share the same new keychain service but use different entry keys,
/// so there is no collision.
public protocol TokenStore: Sendable {
    func setToken(_ token: OAuthToken, provider: ProviderID, profile: String) throws
    func token(provider: ProviderID, profile: String) throws -> OAuthToken?
    func deleteToken(provider: ProviderID, profile: String) throws
}

extension TokenStore {
    static func account(provider: ProviderID, profile: String) -> String {
        "\(profile)/\(provider.rawValue)"
    }
}

/// SymairaKeychain-backed production store for OAuth tokens.
///
/// OAuth tokens are serialised to JSON strings before being stored and
/// deserialised on read. The migration path from the legacy service
/// (`com.symaira.terminal.oauth`) is shared with `KeychainKeyStore` via the
/// same per-profile sentinel mechanism so each profile is migrated at most
/// once regardless of which store is accessed first.
public struct KeychainTokenStore: TokenStore {
    /// Legacy service name for OAuth tokens — used during migration only.
    private static let legacyOAuthService = "com.symaira.terminal.oauth"
    /// Legacy service name for API keys — also checked during migration
    /// in case KeychainKeyStore has not run yet.
    private static let legacyAPIKeyService = "com.symaira.terminal.byok"
    /// Sentinel key prefix for per-profile migration tracking.
    private static let migrationSentinelPrefix = "migration_done"

    private let keychain: SymairaKeychain
    private let legacyOAuthKeychain: SymairaKeychain
    private let legacyAPIKeychain: SymairaKeychain

    public init() {
        keychain = SymairaKeychain(app: "symaira-terminal")
        legacyOAuthKeychain = SymairaKeychain(service: Self.legacyOAuthService)
        legacyAPIKeychain = SymairaKeychain(service: Self.legacyAPIKeyService)
    }

    // MARK: - Migration

    /// Migrate legacy OAuth tokens (and API keys, if not yet migrated by
    /// `KeychainKeyStore`) for `profile` on first access. Uses the same
    /// sentinel key as `KeychainKeyStore` so migration runs at most once
    /// per profile across both stores.
    private func migrateIfNeeded(profile: String) {
        let sentinelKey = "\(Self.migrationSentinelPrefix)/\(profile)"
        guard (try? keychain.read(key: sentinelKey)) == nil else { return }

        for provider in ProviderID.allCases {
            let account = Self.account(provider: provider, profile: profile)

            // OAuth tokens (this store's primary responsibility)
            if let value = try? legacyOAuthKeychain.read(key: account) {
                _ = try? keychain.save(value, key: account)
                legacyOAuthKeychain.delete(key: account)
            }

            // API keys (migrate if KeychainKeyStore has not run yet)
            if let value = try? legacyAPIKeychain.read(key: account) {
                _ = try? keychain.save(value, key: account)
                legacyAPIKeychain.delete(key: account)
            }
        }

        _ = try? keychain.save("1", key: sentinelKey)
    }

    // MARK: - TokenStore

    public func setToken(_ token: OAuthToken, provider: ProviderID, profile: String) throws {
        migrateIfNeeded(profile: profile)
        let account = Self.account(provider: provider, profile: profile)
        let data = try JSONEncoder().encode(token)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw TokenStoreError.keychainFailure(errSecParam)
        }
        try keychain.save(jsonString, key: account)
    }

    public func token(provider: ProviderID, profile: String) throws -> OAuthToken? {
        migrateIfNeeded(profile: profile)
        let account = Self.account(provider: provider, profile: profile)
        guard let jsonString = try keychain.read(key: account) else { return nil }
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try JSONDecoder().decode(OAuthToken.self, from: data)
    }

    public func deleteToken(provider: ProviderID, profile: String) throws {
        migrateIfNeeded(profile: profile)
        let account = Self.account(provider: provider, profile: profile)
        keychain.delete(key: account)
    }
}

public enum TokenStoreError: Error, Equatable {
    case keychainFailure(OSStatus)
}

/// Test/in-memory store — unit tests must never touch the real Keychain.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: OAuthToken] = [:]

    public init() {}

    public func setToken(_ token: OAuthToken, provider: ProviderID, profile: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[Self.account(provider: provider, profile: profile)] = token
    }

    public func token(provider: ProviderID, profile: String) throws -> OAuthToken? {
        lock.lock(); defer { lock.unlock() }
        return storage[Self.account(provider: provider, profile: profile)]
    }

    public func deleteToken(provider: ProviderID, profile: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[Self.account(provider: provider, profile: profile)] = nil
    }
}
