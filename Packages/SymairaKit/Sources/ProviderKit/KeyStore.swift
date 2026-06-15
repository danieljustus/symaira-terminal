import Foundation
import Security

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
    /// The authentication method for this provider.
    public var authMethod: AuthMethod {
        switch self {
        case .openai:
            return .oauth(.openAI)
        case .google:
            return .oauth(.google)
        case .anthropic, .openrouter, .ollama, .openAICompatible:
            return .apiKey
        }
    }

    /// Whether this provider supports OAuth sign-in.
    public var supportsOAuth: Bool {
        if case .oauth = authMethod { return true }
        return false
    }

    /// The OAuth configuration for this provider, if available.
    public var oauthConfig: OAuthConfig? {
        if case .oauth(let config) = authMethod { return config }
        return nil
    }
}

public enum KeyStoreError: Error, Equatable {
    case keychainFailure(OSStatus)
}

/// Storage for BYOK API keys. Keys never touch config files, logs, or any
/// Symaira service — the production implementation is the macOS Keychain.
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

/// Keychain-backed production store (kSecClassGenericPassword, app-scoped service).
public struct KeychainKeyStore: KeyStore {
    public static let service = "com.symaira.terminal.byok"

    public init() {}

    public func setKey(_ key: String, provider: ProviderID, profile: String) throws {
        let account = Self.account(provider: provider, profile: profile)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: account,
        ]
        let attributes: [CFString: Any] = [kSecValueData: Data(key.utf8)]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let addQuery = query.merging(attributes) { _, new in new }
                .merging([kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]) { _, new in new }
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeyStoreError.keychainFailure(status) }
    }

    public func key(provider: ProviderID, profile: String) throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: Self.account(provider: provider, profile: profile),
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeyStoreError.keychainFailure(status)
        }
        return String(data: data, encoding: .utf8)
    }

    public func deleteKey(provider: ProviderID, profile: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: Self.account(provider: provider, profile: profile),
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeyStoreError.keychainFailure(status)
        }
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
