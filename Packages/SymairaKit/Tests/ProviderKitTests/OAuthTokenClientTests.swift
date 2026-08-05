import Foundation
import Testing
@testable import ProviderKit

// MARK: - Mock URL protocol

/// URLProtocol stub that answers every request from a scripted closure.
/// Requests never leave the process. The whole suite is serialized so the
/// shared static handler is never read by two tests at once.
private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (status, body) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func makeClient(handler: @escaping (URLRequest) throws -> (Int, Data)) -> OAuthTokenClient {
    MockURLProtocol.handler = handler
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)
    return OAuthTokenClient(session: session)
}

/// URLProtocol mocks deliver the request body via the body stream, not
/// `httpBody`. Read both so body assertions work regardless of transport.
private func requestBodyString(_ request: URLRequest) -> String {
    if let body = request.httpBody {
        return String(data: body, encoding: .utf8) ?? ""
    }
    guard let stream = request.httpBodyStream else { return "" }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufferSize = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
        let read = stream.read(buffer, maxLength: bufferSize)
        guard read > 0 else { break }
        data.append(buffer, count: read)
    }
    return String(data: data, encoding: .utf8) ?? ""
}

private let testConfig = OAuthConfig(
    clientId: "test-client",
    authorizationEndpoint: URL(string: "https://example.test/authorize")!,
    tokenEndpoint: URL(string: "https://example.test/token")!,
    scopes: ["openid", "profile"],
    redirectURIScheme: "symaira-oauth"
)

private func tokenBody(
    accessToken: String = "at-123",
    refreshToken: String? = "rt-456",
    expiresIn: Int? = 3600,
    scope: String? = "openid profile"
) -> String {
    var parts: [String] = ["\"access_token\":\"\(accessToken)\""]
    if let refreshToken { parts.append("\"refresh_token\":\"\(refreshToken)\"") }
    if let expiresIn { parts.append("\"expires_in\":\(expiresIn)") }
    parts.append("\"token_type\":\"Bearer\"")
    if let scope { parts.append("\"scope\":\"\(scope)\"") }
    return "{\(parts.joined(separator: ","))}"
}

// MARK: - OAuthTokenClient tests (serialized: shared static handler)

@Suite(.serialized) struct OAuthTokenClientTests {
    // MARK: Exchange code

    @Test func exchangesCodeSuccessfully() async throws {
        let client = makeClient { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url == testConfig.tokenEndpoint)
            let body = requestBodyString(request)
            #expect(body.contains("grant_type=authorization_code"))
            #expect(body.contains("code=the-code"))
            #expect(body.contains("code_verifier=verifier"))
            #expect(body.contains("client_id=test-client"))
            return (200, Data(tokenBody().utf8))
        }

        let token = try await client.exchangeCode("the-code", config: testConfig, codeVerifier: "verifier")
        #expect(token.accessToken == "at-123")
        #expect(token.refreshToken == "rt-456")
        #expect(token.tokenType == "Bearer")
        #expect(token.scope == "openid profile")
        #expect(token.expiresAt != nil)
    }

    @Test func throwsOnMalformedResponse() async throws {
        let client = makeClient { _ in (200, Data("not json at all".utf8)) }
        do {
            _ = try await client.exchangeCode("code", config: testConfig, codeVerifier: "v")
            Issue.record("Expected a decoding error")
        } catch is DecodingError {
            // expected: a 200 with invalid JSON fails token decoding
        }
    }

    @Test func throwsOnMissingAccessToken() async throws {
        // 200 with a body that lacks access_token (e.g. only refresh_token).
        let client = makeClient { _ in (200, Data("{\"refresh_token\":\"rt-1\"}".utf8)) }
        do {
            _ = try await client.exchangeCode("code", config: testConfig, codeVerifier: "v")
            Issue.record("Expected OAuthError.noAccessToken")
        } catch let error as OAuthError {
            if case .noAccessToken = error {
                // expected
            } else {
                Issue.record("Expected noAccessToken, got \(error)")
            }
        }
    }

    @Test func throwsOnHttpErrorWithSanitizedDetail() async throws {
        let client = makeClient { _ in (400, Data("{\"error\":\"invalid_grant\"}".utf8)) }
        do {
            _ = try await client.exchangeCode("code", config: testConfig, codeVerifier: "v")
            Issue.record("Expected OAuthError.tokenExchangeFailed")
        } catch let error as OAuthError {
            if case .tokenExchangeFailed(let detail) = error {
                #expect(detail.contains("HTTP 400"))
            } else {
                Issue.record("Expected tokenExchangeFailed, got \(error)")
            }
        }
    }

    @Test func throwsOnNetworkFailure() async throws {
        let client = makeClient { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await client.exchangeCode("code", config: testConfig, codeVerifier: "v")
            Issue.record("Expected a URLError")
        } catch is URLError {
            // expected
        }
    }

    // MARK: Refresh

    @Test func refreshesToken() async throws {
        let client = makeClient { request in
            let body = requestBodyString(request)
            #expect(body.contains("grant_type=refresh_token"))
            #expect(body.contains("refresh_token=rt-old"))
            return (200, Data(tokenBody(accessToken: "at-new", refreshToken: "rt-new").utf8))
        }

        let token = try await client.refreshToken("rt-old", config: testConfig)
        #expect(token.accessToken == "at-new")
        #expect(token.refreshToken == "rt-new") // rotation
    }

    @Test func keepsRefreshTokenWhenResponseOmitsIt() async throws {
        let client = makeClient { _ in
            (200, Data(tokenBody(accessToken: "at-new", refreshToken: nil).utf8))
        }

        let token = try await client.refreshToken("rt-old", config: testConfig)
        #expect(token.accessToken == "at-new")
        #expect(token.refreshToken == "rt-old") // falls back to the sent one
    }

    @Test func throwsOnInvalidGrant() async throws {
        let client = makeClient { _ in (400, Data("{\"error\":\"invalid_grant\"}".utf8)) }
        do {
            _ = try await client.refreshToken("rt-old", config: testConfig)
            Issue.record("Expected OAuthError.refreshTokenFailed")
        } catch let error as OAuthError {
            if case .refreshTokenFailed = error {
                // expected
            } else {
                Issue.record("Expected refreshTokenFailed, got \(error)")
            }
        }
    }

    @Test func throwsOn401Reauth() async throws {
        let client = makeClient { _ in (401, Data("{\"error\":\"unauthorized\"}".utf8)) }
        do {
            _ = try await client.refreshToken("rt-old", config: testConfig)
            Issue.record("Expected OAuthError.refreshTokenFailed")
        } catch let error as OAuthError {
            if case .refreshTokenFailed = error {
                // expected
            } else {
                Issue.record("Expected refreshTokenFailed, got \(error)")
            }
        }
    }

    @Test func throwsOnNetworkFailureDuringRefresh() async throws {
        let client = makeClient { _ in throw URLError(.timedOut) }
        do {
            _ = try await client.refreshToken("rt-old", config: testConfig)
            Issue.record("Expected a URLError")
        } catch is URLError {
            // expected
        }
    }

    // MARK: validAccessToken

    @Test func returnsValidTokenWithoutNetworkCall() async throws {
        let store = InMemoryTokenStore()
        var networkCalled = false
        let client = makeClient { _ in
            networkCalled = true
            return (200, Data(tokenBody().utf8))
        }

        let access = try await client.validAccessToken(
            for: futureToken(), config: testConfig, tokenStore: store, provider: .openai, profile: "default"
        )
        #expect(access == "at-valid")
        #expect(!networkCalled)
        #expect(try store.token(provider: .openai, profile: "default") == nil)
    }

    @Test func refreshesExpiredTokenAndPersists() async throws {
        let store = InMemoryTokenStore()
        let client = makeClient { _ in
            (200, Data(tokenBody(accessToken: "at-refreshed", refreshToken: "rt-new").utf8))
        }

        let access = try await client.validAccessToken(
            for: expiredToken(), config: testConfig, tokenStore: store, provider: .openai, profile: "default"
        )
        #expect(access == "at-refreshed")
        let stored = try store.token(provider: .openai, profile: "default")
        #expect(stored?.accessToken == "at-refreshed")
        #expect(stored?.refreshToken == "rt-new")
    }

    @Test func throwsWhenExpiredAndNoRefreshToken() async throws {
        let store = InMemoryTokenStore()
        let client = makeClient { _ in (500, Data("unreachable".utf8)) }

        let noRefresh = OAuthToken(
            accessToken: "at-expired", refreshToken: nil,
            expiresAt: Date().addingTimeInterval(-60), scope: nil
        )
        do {
            _ = try await client.validAccessToken(for: noRefresh, config: testConfig, tokenStore: store, provider: .openai, profile: "default")
            Issue.record("Expected OAuthError.noRefreshToken")
        } catch let error as OAuthError {
            if case .noRefreshToken = error {
                // expected
            } else {
                Issue.record("Expected noRefreshToken, got \(error)")
            }
        }
    }

    @Test func propagatesRefreshFailureWithoutStoringPartialToken() async throws {
        let store = InMemoryTokenStore()
        let client = makeClient { _ in (401, Data("{\"error\":\"unauthorized\"}".utf8)) }

        do {
            _ = try await client.validAccessToken(
                for: expiredToken(), config: testConfig, tokenStore: store, provider: .openai, profile: "default"
            )
            Issue.record("Expected OAuthError.refreshTokenFailed")
        } catch let error as OAuthError {
            if case .refreshTokenFailed = error {
                // expected
            } else {
                Issue.record("Expected refreshTokenFailed, got \(error)")
            }
        }
        #expect(try store.token(provider: .openai, profile: "default") == nil)
    }

    // MARK: - Helpers

    private func futureToken() -> OAuthToken {
        OAuthToken(
            accessToken: "at-valid",
            refreshToken: "rt-1",
            expiresAt: Date().addingTimeInterval(3600),
            scope: "openid"
        )
    }

    private func expiredToken() -> OAuthToken {
        OAuthToken(
            accessToken: "at-expired",
            refreshToken: "rt-1",
            expiresAt: Date().addingTimeInterval(-60),
            scope: "openid"
        )
    }
}
