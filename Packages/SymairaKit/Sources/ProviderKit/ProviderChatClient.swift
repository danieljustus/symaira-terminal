import Foundation

public enum ProviderError: Error, LocalizedError {
    case invalidKey
    case rateLimited
    case serverError(Int)
    case decodingFailed
    case networkError(Error)
    case missingKey
    case timeout
    case missingBaseURL
    case invalidBaseURL

    public var errorDescription: String? {
        switch self {
        case .invalidKey: return "Invalid API key. Check your provider settings."
        case .rateLimited: return "Rate limited. Try again shortly."
        case .serverError(let code): return "Server error (HTTP \(code))."
        case .decodingFailed: return "Unexpected response from provider."
        case .networkError(let error): return error.localizedDescription
        case .missingKey: return "No API key configured. Go to Settings → Providers to add one."
        case .timeout: return "Request timed out. The provider may be slow or unavailable."
        case .missingBaseURL: return "No base URL configured for OpenAI-compatible provider. Go to Settings → Providers to set one."
        case .invalidBaseURL: return "Invalid base URL. Use https:// (or http:// for localhost only)."
        }
    }
}

/// A wrapper that redacts the secret value in `description` and `debugDescription`
/// to prevent accidental logging of API keys.
public struct Secret<Value: Sendable>: Sendable {
    public let value: Value

    public init(_ value: Value) {
        self.value = value
    }

    public var description: String { "[REDACTED]" }
    public var debugDescription: String { "[REDACTED]" }
}

struct ProviderDescriptor: Sendable {
    let endpoint: @Sendable (ProviderID, WorkspaceConfig.ProfileConfig?) -> URL
    let authHeader: @Sendable (String?) -> [String: String]
    let requestBody: @Sendable (ProviderID, String, String, Int, WorkspaceConfig.ProfileConfig?) -> [String: Any]
    let parseResponse: @Sendable (Data, ProviderID) throws -> String
    let defaultModel: @Sendable (ProviderID) -> String
}

public struct ProviderChatClient: Sendable {
    /// Canonical per-provider default models. Update this table to change defaults
    /// without touching any other code. `ProviderSettingsView` surfaces these so
    /// users see the active default before they set a custom value.
    public static let defaultModels: [ProviderID: String] = [
        .anthropic: "claude-sonnet-4-20250514",
        .openai: "gpt-4o",
        .openAICompatible: "",           // user must configure explicitly
        .openrouter: "anthropic/claude-sonnet-4",
        .google: "gemini-2.5-flash",
        .ollama: "llama3.1"
    ]

    private let keyStore: KeyStore
    private let tokenStore: TokenStore
    private let descriptors: [ProviderID: ProviderDescriptor]

    public init(keyStore: KeyStore = KeychainKeyStore(), tokenStore: TokenStore = KeychainTokenStore()) {
        self.keyStore = keyStore
        self.tokenStore = tokenStore
        self.descriptors = Self.buildDescriptors()
    }

    private static func buildDescriptors() -> [ProviderID: ProviderDescriptor] {
        [
            .anthropic: ProviderDescriptor(
                endpoint: { _, _ in URL(string: "https://api.anthropic.com/v1/messages")! },
                authHeader: { apiKey in
                    [
                        "x-api-key": apiKey ?? "",
                        "anthropic-version": "2023-06-01",
                        "content-type": "application/json"
                    ]
                },
                requestBody: { provider, systemPrompt, userMessage, maxTokens, profileConfig in
                    let model = profileConfig?.model ?? defaultModels[provider] ?? ""
                    return [
                        "model": model,
                        "system": systemPrompt,
                        "messages": [["role": "user", "content": userMessage]],
                        "max_tokens": maxTokens
                    ]
                },
                parseResponse: { data, _ in
                    let response = try JSONDecoder().decode(AnthropicResponse.self, from: data)
                    return response.content.first?.text ?? ""
                },
                defaultModel: { provider in defaultModels[provider] ?? "" }
            ),
            .openai: ProviderDescriptor(
                endpoint: { _, _ in URL(string: "https://api.openai.com/v1/chat/completions")! },
                authHeader: { apiKey in
                    [
                        "Authorization": "Bearer \(apiKey ?? "")",
                        "content-type": "application/json"
                    ]
                },
                requestBody: { provider, systemPrompt, userMessage, maxTokens, profileConfig in
                    let model = profileConfig?.model ?? defaultModels[provider] ?? ""
                    return [
                        "model": model,
                        "messages": [
                            ["role": "system", "content": systemPrompt],
                            ["role": "user", "content": userMessage]
                        ],
                        "max_tokens": maxTokens
                    ]
                },
                parseResponse: { data, _ in
                    let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)
                    return response.choices.first?.message.content ?? ""
                },
                defaultModel: { provider in defaultModels[provider] ?? "" }
            ),
            .openAICompatible: ProviderDescriptor(
                endpoint: { _, profileConfig in
                    let baseURL = profileConfig?.baseURL ?? "https://api.openai.com/v1"
                    let baseURLString = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
                    return URL(string: "\(baseURLString)/chat/completions")!
                },
                authHeader: { apiKey in
                    [
                        "Authorization": "Bearer \(apiKey ?? "")",
                        "content-type": "application/json"
                    ]
                },
                requestBody: { provider, systemPrompt, userMessage, maxTokens, profileConfig in
                    let model = profileConfig?.model ?? defaultModels[provider] ?? ""
                    return [
                        "model": model,
                        "messages": [
                            ["role": "system", "content": systemPrompt],
                            ["role": "user", "content": userMessage]
                        ],
                        "max_tokens": maxTokens
                    ]
                },
                parseResponse: { data, _ in
                    let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)
                    return response.choices.first?.message.content ?? ""
                },
                defaultModel: { provider in defaultModels[provider] ?? "" }
            ),
            .openrouter: ProviderDescriptor(
                endpoint: { _, _ in URL(string: "https://openrouter.ai/api/v1/chat/completions")! },
                authHeader: { apiKey in
                    [
                        "Authorization": "Bearer \(apiKey ?? "")",
                        "content-type": "application/json"
                    ]
                },
                requestBody: { provider, systemPrompt, userMessage, maxTokens, profileConfig in
                    let model = profileConfig?.model ?? defaultModels[provider] ?? ""
                    return [
                        "model": model,
                        "messages": [
                            ["role": "system", "content": systemPrompt],
                            ["role": "user", "content": userMessage]
                        ],
                        "max_tokens": maxTokens
                    ]
                },
                parseResponse: { data, _ in
                    let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)
                    return response.choices.first?.message.content ?? ""
                },
                defaultModel: { provider in defaultModels[provider] ?? "" }
            ),
            .google: ProviderDescriptor(
                // Model is part of the Google REST URL path; use profileConfig.model
                // or the default from the table so the endpoint stays data-driven.
                endpoint: { _, profileConfig in
                    let model = profileConfig?.model ?? defaultModels[.google] ?? "gemini-2.5-flash"
                    return URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
                },
                authHeader: { apiKey in
                    [
                        "x-goog-api-key": apiKey ?? "",
                        "content-type": "application/json"
                    ]
                },
                requestBody: { _, systemPrompt, userMessage, _, _ in
                    return [
                        "contents": [["parts": [["text": systemPrompt + "\n\n" + userMessage]]]]
                    ]
                },
                parseResponse: { data, _ in
                    let response = try JSONDecoder().decode(GoogleResponse.self, from: data)
                    return response.candidates.first?.content.parts.first?.text ?? ""
                },
                defaultModel: { provider in defaultModels[provider] ?? "" }
            ),
            .ollama: ProviderDescriptor(
                endpoint: { _, _ in URL(string: "http://localhost:11434/api/generate")! },
                authHeader: { _ in ["content-type": "application/json"] },
                requestBody: { provider, systemPrompt, userMessage, _, profileConfig in
                    let model = profileConfig?.model ?? defaultModels[provider] ?? ""
                    return [
                        "model": model,
                        "prompt": systemPrompt + "\n\n" + userMessage,
                        "stream": false
                    ]
                },
                parseResponse: { data, _ in
                    let response = try JSONDecoder().decode(OllamaResponse.self, from: data)
                    return response.response
                },
                defaultModel: { provider in defaultModels[provider] ?? "" }
            )
        ]
    }

    public func complete(
        system systemPrompt: String,
        user userMessage: String,
        provider: ProviderID,
        profile: String,
        maxTokens: Int = 256,
        profileConfig: WorkspaceConfig.ProfileConfig? = nil
    ) async throws -> String {
        guard let descriptor = descriptors[provider] else {
            throw ProviderError.networkError(NSError(domain: "ProviderKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown provider"]))
        }

        let secretKey: Secret<String>
        if provider.supportsOAuth {
            guard let token = try tokenStore.token(provider: provider, profile: profile) else {
                throw ProviderError.missingKey
            }
            let tokenClient = OAuthTokenClient()
            let accessToken = try await tokenClient.validAccessToken(
                for: token,
                config: provider.oauthConfig!,
                tokenStore: tokenStore,
                provider: provider,
                profile: profile
            )
            secretKey = Secret(accessToken)
        } else {
            secretKey = Secret(try keyStore.key(provider: provider, profile: profile) ?? "")
        }

        if provider != .ollama {
            guard !secretKey.value.isEmpty else {
                throw ProviderError.missingKey
            }
        }

        if provider == .openAICompatible {
            guard let baseURLString = profileConfig?.baseURL, !baseURLString.isEmpty else {
                throw ProviderError.missingBaseURL
            }
            guard let url = URL(string: baseURLString),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "https" || (scheme == "http" && url.host == "localhost") else {
                throw ProviderError.invalidBaseURL
            }
        }

        let url = descriptor.endpoint(provider, profileConfig)
        let headers = descriptor.authHeader(secretKey.value)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let body = descriptor.requestBody(provider, systemPrompt, userMessage, maxTokens, profileConfig)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw ProviderError.timeout
        } catch {
            throw ProviderError.networkError(error)
        }

        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 401, 403: throw ProviderError.invalidKey
            case 429: throw ProviderError.rateLimited
            default: break
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw ProviderError.serverError(httpResponse.statusCode)
            }
        }

        return try descriptor.parseResponse(data, provider)
    }
}

// MARK: - Response Types

struct AnthropicResponse: Codable {
    let content: [AnthropicContent]
}

struct AnthropicContent: Codable {
    let text: String
}

struct GoogleResponse: Codable {
    let candidates: [GoogleCandidate]
}

struct GoogleCandidate: Codable {
    let content: GoogleContent
}

struct GoogleContent: Codable {
    let parts: [GooglePart]
}

struct GooglePart: Codable {
    let text: String
}

struct OllamaResponse: Codable {
    let response: String
}

struct OpenAIResponse: Codable {
    let choices: [OpenAIChoice]
}

struct OpenAIChoice: Codable {
    let message: OpenAIMessage
}

struct OpenAIMessage: Codable {
    let content: String
}
