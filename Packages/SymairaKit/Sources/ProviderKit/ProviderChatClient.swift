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

public struct ProviderChatClient: Sendable {
    private let keyStore: KeyStore

    public init(keyStore: KeyStore = KeychainKeyStore()) {
        self.keyStore = keyStore
    }

    public func complete(
        system systemPrompt: String,
        user userMessage: String,
        provider: ProviderID,
        profile: String,
        maxTokens: Int = 256,
        profileConfig: WorkspaceConfig.ProfileConfig? = nil
    ) async throws -> String {
        // Fail fast if no key configured (except Ollama which doesn't need one)
        if provider != .ollama {
            let apiKey = try keyStore.key(provider: provider, profile: profile)
            guard let key = apiKey, !key.isEmpty else {
                throw ProviderError.missingKey
            }
        }

        // Validate baseURL for openAICompatible
        if provider == .openAICompatible {
            guard let baseURLString = profileConfig?.baseURL, !baseURLString.isEmpty else {
                throw ProviderError.missingBaseURL
            }
            guard let url = URL(string: baseURLString),
                  let scheme = url.scheme?.lowercased(),
                  (scheme == "https" || (scheme == "http" && url.host == "localhost")) else {
                throw ProviderError.invalidBaseURL
            }
        }

        let apiKey = try keyStore.key(provider: provider, profile: profile)
        let request = try buildRequest(
            provider: provider,
            apiKey: apiKey,
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            maxTokens: maxTokens,
            profileConfig: profileConfig
        )

        let data: Data
        let response: URLResponse
        do {
            let urlRequest = request
            (data, response) = try await URLSession.shared.data(for: urlRequest)
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

        return try parseResponse(data: data, provider: provider)
    }

    // MARK: - Request Building

    private func buildRequest(
        provider: ProviderID,
        apiKey: String?,
        systemPrompt: String,
        userMessage: String,
        maxTokens: Int,
        profileConfig: WorkspaceConfig.ProfileConfig? = nil
    ) throws -> URLRequest {
        let url: URL
        var headers: [String: String]

        switch provider {
        case .anthropic:
            url = URL(string: "https://api.anthropic.com/v1/messages")!
            headers = [
                "x-api-key": apiKey ?? "",
                "anthropic-version": "2023-06-01",
                "content-type": "application/json"
            ]
        case .openai:
            url = URL(string: "https://api.openai.com/v1/chat/completions")!
            headers = [
                "Authorization": "Bearer \(apiKey ?? "")",
                "content-type": "application/json"
            ]
        case .openAICompatible:
            let baseURL = profileConfig?.baseURL ?? "https://api.openai.com/v1"
            let baseURLString = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
            url = URL(string: "\(baseURLString)/chat/completions")!
            headers = [
                "Authorization": "Bearer \(apiKey ?? "")",
                "content-type": "application/json"
            ]
        case .openrouter:
            url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
            headers = [
                "Authorization": "Bearer \(apiKey ?? "")",
                "content-type": "application/json"
            ]
        case .google:
            url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!
            headers = [
                "x-goog-api-key": apiKey ?? "",
                "content-type": "application/json"
            ]
        case .ollama:
            url = URL(string: "http://localhost:11434/api/generate")!
            headers = ["content-type": "application/json"]
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let body = buildBody(
            provider: provider,
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            maxTokens: maxTokens,
            profileConfig: profileConfig
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return request
    }

    private func buildBody(
        provider: ProviderID,
        systemPrompt: String,
        userMessage: String,
        maxTokens: Int,
        profileConfig: WorkspaceConfig.ProfileConfig? = nil
    ) -> [String: Any] {
        let model = profileConfig?.model ?? defaultModel(for: provider)
        switch provider {
        case .anthropic:
            return [
                "model": model,
                "system": systemPrompt,
                "messages": [["role": "user", "content": userMessage]],
                "max_tokens": maxTokens
            ]
        case .google:
            return [
                "contents": [["parts": [["text": systemPrompt + "\n\n" + userMessage]]]]
            ]
        case .ollama:
            return [
                "model": model,
                "prompt": systemPrompt + "\n\n" + userMessage,
                "stream": false
            ]
        case .openai, .openAICompatible, .openrouter:
            return [
                "model": model,
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": userMessage]
                ],
                "max_tokens": maxTokens
            ]
        }
    }

    // MARK: - Response Parsing

    private func parseResponse(data: Data, provider: ProviderID) throws -> String {
        switch provider {
        case .anthropic:
            let response = try JSONDecoder().decode(AnthropicResponse.self, from: data)
            return response.content.first?.text ?? ""
        case .google:
            let response = try JSONDecoder().decode(GoogleResponse.self, from: data)
            return response.candidates.first?.content.parts.first?.text ?? ""
        case .ollama:
            let response = try JSONDecoder().decode(OllamaResponse.self, from: data)
            return response.response
        case .openai, .openAICompatible, .openrouter:
            let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            return response.choices.first?.message.content ?? ""
        }
    }

    private func defaultModel(for provider: ProviderID) -> String {
        switch provider {
        case .anthropic: return "claude-3-5-sonnet-20241022"
        case .openai: return "gpt-4o"
        case .openrouter: return "anthropic/claude-3-5-sonnet"
        case .google: return "gemini-pro"
        case .ollama: return "llama3"
        case .openAICompatible: return "default"
        }
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
