import Foundation
import ProviderKit

public struct FixErrorService: Sendable {
    private let keyStore: KeyStore

    public init(keyStore: KeyStore = KeychainKeyStore()) {
        self.keyStore = keyStore
    }

    public func buildPrompt(commandOutput: String, provider: ProviderID, profile: String) async throws -> String? {
        guard let apiKey = try keyStore.key(provider: provider, profile: profile) else {
            return nil
        }

        let systemPrompt = """
        You are a helpful assistant that analyzes command errors and suggests fixes.
        Given the command output below, identify the error and suggest a fix.
        Be concise and provide actionable steps.

        Command output:
        \(commandOutput)
        """

        let request = try buildRequest(
            provider: provider,
            apiKey: apiKey,
            systemPrompt: systemPrompt,
            userMessage: "Analyze this error and suggest a fix:"
        )

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(ChatResponse.self, from: data)
        return response.choices.first?.message.content
    }

    private func buildRequest(provider: ProviderID, apiKey: String, systemPrompt: String, userMessage: String) throws -> URLRequest {
        let url: URL
        var headers: [String: String]

        switch provider {
        case .anthropic:
            url = URL(string: "https://api.anthropic.com/v1/messages")!
            headers = [
                "x-api-key": apiKey,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json"
            ]
        case .openai, .openAICompatible:
            url = URL(string: "https://api.openai.com/v1/chat/completions")!
            headers = [
                "Authorization": "Bearer \(apiKey)",
                "content-type": "application/json"
            ]
        case .openrouter:
            url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
            headers = [
                "Authorization": "Bearer \(apiKey)",
                "content-type": "application/json"
            ]
        case .google:
            url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent?key=\(apiKey)")!
            headers = ["content-type": "application/json"]
        case .ollama:
            url = URL(string: "http://localhost:11434/api/generate")!
            headers = ["content-type": "application/json"]
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let body: [String: Any] = [
            "model": defaultModel(for: provider),
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ],
            "max_tokens": 1024
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return request
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

struct ChatResponse: Codable {
    let choices: [Choice]
}

struct Choice: Codable {
    let message: Message
}

struct Message: Codable {
    let content: String
}
