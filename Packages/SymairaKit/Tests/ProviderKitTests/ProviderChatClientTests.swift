import Foundation
import Testing
@testable import ProviderKit

@Suite struct ProviderChatClientTests {
    @Test func parseAnthropicResponse() throws {
        let json = Data("""
        {"content":[{"text":"ls -la"}]}
        """.utf8)
        let response = try JSONDecoder().decode(AnthropicResponse.self, from: json)
        #expect(response.content.first?.text == "ls -la")
    }

    @Test func parseOpenAIResponse() throws {
        let json = Data("""
        {"choices":[{"message":{"content":"git status"}}]}
        """.utf8)
        let response = try JSONDecoder().decode(OpenAIResponse.self, from: json)
        #expect(response.choices.first?.message.content == "git status")
    }

    @Test func parseGoogleResponse() throws {
        let json = Data("""
        {"candidates":[{"content":{"parts":[{"text":"echo hello"}]}}]}
        """.utf8)
        let response = try JSONDecoder().decode(GoogleResponse.self, from: json)
        #expect(response.candidates.first?.content.parts.first?.text == "echo hello")
    }

    @Test func parseOllamaResponse() throws {
        let json = Data("""
        {"response":"cat file.txt"}
        """.utf8)
        let response = try JSONDecoder().decode(OllamaResponse.self, from: json)
        #expect(response.response == "cat file.txt")
    }

    @Test func providerErrorDescriptions() {
        #expect(ProviderError.invalidKey.errorDescription?.contains("Invalid API key") == true)
        #expect(ProviderError.rateLimited.errorDescription?.contains("Rate limited") == true)
        #expect(ProviderError.serverError(500).errorDescription?.contains("500") == true)
    }
}
