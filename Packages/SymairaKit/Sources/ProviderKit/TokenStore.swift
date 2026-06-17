import Foundation
import Security

/// Storage for OAuth tokens. Tokens live in the macOS Keychain only — never
/// in config files, logs, or any Symaira service.
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

/// Keychain-backed production store for OAuth tokens.
public struct KeychainTokenStore: TokenStore {
    public static let service = "com.symaira.terminal.oauth"

    public init() {}

    public func setToken(_ token: OAuthToken, provider: ProviderID, profile: String) throws {
        let account = Self.account(provider: provider, profile: profile)
        let data = try JSONEncoder().encode(token)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: account
        ]
        let attributes: [CFString: Any] = [kSecValueData: data]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let addQuery = query.merging(attributes) { _, new in new }
                .merging([kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]) { _, new in new }
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw TokenStoreError.keychainFailure(status) }
    }

    public func token(provider: ProviderID, profile: String) throws -> OAuthToken? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: Self.account(provider: provider, profile: profile),
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw TokenStoreError.keychainFailure(status)
        }
        return try JSONDecoder().decode(OAuthToken.self, from: data)
    }

    public func deleteToken(provider: ProviderID, profile: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: Self.account(provider: provider, profile: profile)
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TokenStoreError.keychainFailure(status)
        }
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
