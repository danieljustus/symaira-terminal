import Foundation

/// A resolved credential for a provider, carrying the actual secret value
/// needed to authenticate API requests. This is the typed bridge between
/// `KeyStore`/`TokenStore` lookups and HTTP header construction.
///
/// The credential is produced by `ProviderChatClient.resolveCredential()` and
/// consumed by each provider's `credentialToHeaders` closure in
/// `ProviderDescriptor`.
public enum ProviderCredential: Sendable {
    /// A static API key (stored in Keychain via `KeyStore`).
    case apiKey(Secret<String>)
    /// An OAuth 2.0 Bearer token (stored in Keychain via `TokenStore`).
    case oauthBearer(Secret<String>)
    /// No credential required (e.g. Ollama on localhost).
    case none

    public static func == (lhs: ProviderCredential, rhs: ProviderCredential) -> Bool {
        switch (lhs, rhs) {
        case (.apiKey(let a), .apiKey(let b)): return a.value == b.value
        case (.oauthBearer(let a), .oauthBearer(let b)): return a.value == b.value
        case (.none, .none): return true
        default: return false
        }
    }

    /// The raw secret value, if any.
    public var secretValue: String? {
        switch self {
        case .apiKey(let secret): return secret.value
        case .oauthBearer(let secret): return secret.value
        case .none: return nil
        }
    }

    /// Whether this credential is empty/missing (for providers that require one).
    public var isEmpty: Bool {
        switch self {
        case .apiKey(let secret): return secret.value.isEmpty
        case .oauthBearer(let secret): return secret.value.isEmpty
        case .none: return true
        }
    }
}
