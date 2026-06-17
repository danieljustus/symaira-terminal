import Foundation
import CommonCrypto

/// Authentication method for a provider.
public enum AuthMethod: Sendable, Codable {
    /// Static API key (existing BYOK model).
    case apiKey
    /// OAuth 2.0 with PKCE (browser-based sign-in).
    case oauth(OAuthConfig)
}

/// Configuration for an OAuth 2.0 provider.
public struct OAuthConfig: Sendable, Codable {
    /// The OAuth client ID registered with the provider.
    public let clientId: String

    /// The authorization endpoint URL (browser opens this).
    public let authorizationEndpoint: URL

    /// The token endpoint URL (used for token exchange and refresh).
    public let tokenEndpoint: URL

    /// Scopes to request (e.g. ["openid", "profile", "offline_access"]).
    public let scopes: [String]

    /// Custom URL scheme for the redirect (e.g. "symaira-oauth").
    public let redirectURIScheme: String

    public init(
        clientId: String,
        authorizationEndpoint: URL,
        tokenEndpoint: URL,
        scopes: [String],
        redirectURIScheme: String = "symaira-oauth"
    ) {
        self.clientId = clientId
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.scopes = scopes
        self.redirectURIScheme = redirectURIScheme
    }
}

/// An OAuth 2.0 token set stored in the Keychain.
public struct OAuthToken: Sendable, Codable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date?
    public let tokenType: String
    public let scope: String?

    public init(
        accessToken: String,
        refreshToken: String? = nil,
        expiresAt: Date? = nil,
        tokenType: String = "Bearer",
        scope: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.tokenType = tokenType
        self.scope = scope
    }

    /// Whether the access token is expired or about to expire (within 60s).
    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date().addingTimeInterval(60) >= expiresAt
    }
}

/// PKCE challenge pair for OAuth 2.0 authorization code flow.
public struct PKCEChallenge: Sendable {
    /// The code verifier (random string stored locally).
    public let verifier: String

    /// The code challenge (SHA256 hash of verifier, sent to authorization server).
    public let challenge: String

    /// Create a new PKCE challenge with a random 128-byte verifier.
    public static func generate() -> PKCEChallenge {
        var buffer = [UInt8](repeating: 0, count: 128)
        _ = SecRandomCopyBytes(kSecRandomDefault, 128, &buffer)
        let verifier = Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let inputData = Data(verifier.utf8)
        var hash = [UInt8](repeating: 0, count: 32)
        inputData.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(inputData.count), &hash)
        }
        let challenge = Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        return PKCEChallenge(verifier: verifier, challenge: challenge)
    }
}

// MARK: - OAuth Feature Flag

/// Controls whether OAuth sign-in is exposed in the UI and available for
/// providers. When `false`, OpenAI and Google fall back to API-key mode.
///
/// OAuth is gated because:
/// - Client IDs are placeholders (no real public-client config exists yet)
/// - PKCE verifier plumbing was incomplete
///
/// Set to `true` once real OAuth client registrations are in place and the
/// full flow has been end-to-end tested.
public enum OAuthFeature {
    /// Master switch for OAuth. Currently **off** — providers use API-key mode.
    public static var isEnabled: Bool = false
}

// MARK: - Common OAuth Provider Configurations

extension OAuthConfig {
    /// OpenAI ChatGPT OAuth configuration.
    /// Note: This is a placeholder — OpenAI's OAuth endpoints may change.
    public static let openAI = OAuthConfig(
        clientId: "symaira-terminal",
        authorizationEndpoint: URL(string: "https://auth0.openai.com/authorize")!,
        tokenEndpoint: URL(string: "https://auth0.openai.com/oauth/token")!,
        scopes: ["openid", "profile", "offline_access"],
        redirectURIScheme: "symaira-oauth"
    )

    /// Google OAuth configuration.
    public static let google = OAuthConfig(
        clientId: "symaira-terminal",
        authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
        tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!,
        scopes: ["openid", "profile", "offline_access"],
        redirectURIScheme: "symaira-oauth"
    )
}
