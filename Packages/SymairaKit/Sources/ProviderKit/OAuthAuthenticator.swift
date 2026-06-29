import Foundation
import os
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

private let logger = Logger(subsystem: "com.symaira.OAuthAuthenticator", category: "security")

private func sanitizeDetail(_ raw: String, maxBytes: Int = 200) -> String {
    guard !raw.isEmpty else { return "Unknown error" }
    let truncated: String
    if raw.utf8.count > maxBytes {
        var result = ""
        var byteCount = 0
        for char in raw {
            let charBytes = char.utf8.count
            if byteCount + charBytes > maxBytes { break }
            result.append(char)
            byteCount += charBytes
        }
        truncated = result
    } else {
        truncated = raw
    }
    let patterns: [(regex: String, replacement: String)] = [
        ("sk-ant-[A-Za-z0-9_-]{20,}", "[REDACTED]"),
        ("sk-proj-[A-Za-z0-9]{20,}", "[REDACTED]"),
        ("sk-[A-Za-z0-9]{20,}", "[REDACTED]"),
        ("gh[pousr]_[A-Za-z0-9]{36,}", "[REDACTED]"),
        ("(?i)Bearer\\s+[A-Za-z0-9._~-]{20,}", "Bearer [REDACTED]"),
        ("(?i)(access_token|refresh_token|token)[\"':]\\s*[\"']?[A-Za-z0-9._~-]{20,}", "$1: [REDACTED]")
    ]
    var result = truncated
    for (pattern, replacement) in patterns {
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: replacement)
        }
    }
    return result
}

/// Errors that can occur during OAuth authentication.
public enum OAuthError: Error, LocalizedError {
    case invalidURL(String)
    case tokenExchangeFailed(String)
    case refreshTokenFailed(String)
    case noAccessToken
    case noRefreshToken
    case sessionCancelled
    case sessionFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let reason): return "Invalid OAuth URL: \(reason)"
        case .tokenExchangeFailed(let detail): return "Token exchange failed: \(detail)"
        case .refreshTokenFailed(let detail): return "Token refresh failed: \(detail)"
        case .noAccessToken: return "No access token received."
        case .noRefreshToken: return "No refresh token received."
        case .sessionCancelled: return "Sign-in was cancelled."
        case .sessionFailed(let error): return "Sign-in failed: \(error.localizedDescription)"
        }
    }
}

/// Handles OAuth 2.0 PKCE token exchange and refresh operations.
/// This is non-isolated and can be called from any context.
public struct OAuthTokenClient: Sendable {
    public init() {}

    /// Exchange an authorization code for tokens.
    public func exchangeCode(
        _ code: String,
        config: OAuthConfig,
        codeVerifier: String
    ) async throws -> OAuthToken {
        let redirectURI = "\(config.redirectURIScheme)://callback"

        var request = URLRequest(url: config.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": config.clientId,
            "code_verifier": codeVerifier
        ]

        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let rawDetail = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.debug("Token exchange HTTP \(statusCode) response: \(rawDetail)")
            let sanitized = sanitizeDetail(rawDetail)
            throw OAuthError.tokenExchangeFailed("HTTP \(statusCode): \(sanitized)")
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

        guard let accessToken = tokenResponse.accessToken else {
            throw OAuthError.noAccessToken
        }

        let expiresAt: Date? = tokenResponse.expiresIn.map {
            Date().addingTimeInterval(TimeInterval($0))
        }

        return OAuthToken(
            accessToken: accessToken,
            refreshToken: tokenResponse.refreshToken,
            expiresAt: expiresAt,
            tokenType: tokenResponse.tokenType ?? "Bearer",
            scope: tokenResponse.scope
        )
    }

    /// Refresh an expired access token.
    public func refreshToken(
        _ refreshToken: String,
        config: OAuthConfig
    ) async throws -> OAuthToken {
        var request = URLRequest(url: config.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": config.clientId
        ]

        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let rawDetail = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.debug("Token refresh HTTP \(statusCode) response: \(rawDetail)")
            let sanitized = sanitizeDetail(rawDetail)
            throw OAuthError.refreshTokenFailed("HTTP \(statusCode): \(sanitized)")
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

        guard let accessToken = tokenResponse.accessToken else {
            throw OAuthError.noAccessToken
        }

        let expiresAt: Date? = tokenResponse.expiresIn.map {
            Date().addingTimeInterval(TimeInterval($0))
        }

        let newRefreshToken = tokenResponse.refreshToken ?? refreshToken

        return OAuthToken(
            accessToken: accessToken,
            refreshToken: newRefreshToken,
            expiresAt: expiresAt,
            tokenType: tokenResponse.tokenType ?? "Bearer",
            scope: tokenResponse.scope
        )
    }

    /// Get a valid access token, refreshing if necessary.
    public func validAccessToken(
        for token: OAuthToken,
        config: OAuthConfig,
        tokenStore: TokenStore,
        provider: ProviderID,
        profile: String
    ) async throws -> String {
        if !token.isExpired {
            return token.accessToken
        }

        guard let currentRefreshToken = token.refreshToken else {
            throw OAuthError.noRefreshToken
        }

        let refreshed = try await self.refreshToken(currentRefreshToken, config: config)
        try tokenStore.setToken(refreshed, provider: provider, profile: profile)
        return refreshed.accessToken
    }
}

/// Result of an OAuth authorization request, containing the browser URL
/// and the PKCE code verifier needed for token exchange.
public struct OAuthAuthorizationResult: Sendable {
    public let url: URL
    public let codeVerifier: String

    public init(url: URL, codeVerifier: String) {
        self.url = url
        self.codeVerifier = codeVerifier
    }
}

/// Presents the OAuth 2.0 PKCE browser flow using ASWebAuthenticationSession.
@MainActor
public final class OAuthAuthenticator: NSObject {
    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<URL, Error>?

    public override init() {
        super.init()
    }

    /// Present the OAuth sign-in flow.
    public func authorize(config: OAuthConfig) async throws -> OAuthAuthorizationResult {
        let challenge = PKCEChallenge.generate()
        let redirectURI = "\(config.redirectURIScheme)://callback"

        guard var components = URLComponents(
            url: config.authorizationEndpoint,
            resolvingAgainstBaseURL: false
        ) else {
            throw OAuthError.invalidURL("Cannot build authorization URL")
        }

        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: challenge.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        guard let authURL = components.url else {
            throw OAuthError.invalidURL("Cannot construct authorization URL")
        }

        let callbackURLScheme = config.redirectURIScheme

        let callbackURL = try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackURLScheme
            ) { [weak self] callbackURL, error in
                Task { @MainActor in
                    if let error {
                        continuation.resume(throwing: OAuthError.sessionFailed(error))
                    } else if let callbackURL {
                        continuation.resume(returning: callbackURL)
                    } else {
                        continuation.resume(throwing: OAuthError.sessionCancelled)
                    }
                    self?.session = nil
                    self?.continuation = nil
                }
            }

            session.prefersEphemeralWebBrowserSession = true
            session.presentationContextProvider = self
            self.session = session

            guard session.start() else {
                continuation.resume(throwing: OAuthError.sessionFailed(
                    NSError(domain: "OAuthAuthenticator", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to start authentication session"])
                ))
                self.session = nil
                self.continuation = nil
                return
            }
        }

        return OAuthAuthorizationResult(url: callbackURL, codeVerifier: challenge.verifier)
    }
}

extension OAuthAuthenticator: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}

// MARK: - Token Response (internal)

private struct TokenResponse: Codable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
    let tokenType: String?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case scope
    }
}
