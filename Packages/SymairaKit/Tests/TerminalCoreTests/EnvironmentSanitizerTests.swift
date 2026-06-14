import Foundation
import Testing
@testable import TerminalCore

@Suite("EnvironmentSanitizer")
struct EnvironmentSanitizerTests {
    @Test("Blocked exact names are stripped")
    func blockedNamesStripped() {
        let env: [String: String] = [
            "CLAUDECODE": "1",
            "GOOGLE_API_KEY": "key",
            "GEMINI_API_KEY": "key",
            "PATH": "/usr/bin",
        ]
        let result = EnvironmentSanitizer.sanitize(env)
        #expect(result["CLAUDECODE"] == nil)
        #expect(result["GOOGLE_API_KEY"] == nil)
        #expect(result["GEMINI_API_KEY"] == nil)
        #expect(result["PATH"] == "/usr/bin")
    }

    @Test("Blocked prefixes are stripped")
    func blockedPrefixesStripped() {
        let env: [String: String] = [
            "ANTHROPIC_API_KEY": "key",
            "OPENAI_API_KEY": "key",
            "OPENROUTER_API_KEY": "key",
            "CLAUDE_CODE_MODEL": "claude",
            "AWS_SECRET_ACCESS_KEY": "key",
            "AWS_SECRET_SESSION_TOKEN": "token",
            "AZURE_OPENAI_API_KEY": "key",
            "COHERE_API_KEY": "key",
            "HF_TOKEN": "token",
            "TOGETHER_API_KEY": "key",
            "HUGGINGFACE_HUB_TOKEN": "token",
            "SAFE_VAR": "value",
        ]
        let result = EnvironmentSanitizer.sanitize(env)
        #expect(result["ANTHROPIC_API_KEY"] == nil)
        #expect(result["OPENAI_API_KEY"] == nil)
        #expect(result["OPENROUTER_API_KEY"] == nil)
        #expect(result["CLAUDE_CODE_MODEL"] == nil)
        #expect(result["AWS_SECRET_ACCESS_KEY"] == nil)
        #expect(result["AWS_SECRET_SESSION_TOKEN"] == nil)
        #expect(result["AZURE_OPENAI_API_KEY"] == nil)
        #expect(result["COHERE_API_KEY"] == nil)
        #expect(result["HF_TOKEN"] == nil)
        #expect(result["TOGETHER_API_KEY"] == nil)
        #expect(result["HUGGINGFACE_HUB_TOKEN"] == nil)
        #expect(result["SAFE_VAR"] == "value")
    }

    @Test("Non-sensitive variables pass through")
    func nonSensitivePassThrough() {
        let env: [String: String] = [
            "PATH": "/usr/bin",
            "HOME": "/Users/test",
            "TERM": "xterm-256color",
        ]
        let result = EnvironmentSanitizer.sanitize(env)
        #expect(result == env)
    }

    @Test("Empty environment returns empty")
    func emptyEnvironment() {
        let env: [String: String] = [:]
        let result = EnvironmentSanitizer.sanitize(env)
        #expect(result.isEmpty)
    }
}
