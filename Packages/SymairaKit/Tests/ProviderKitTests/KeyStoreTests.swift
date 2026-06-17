import Testing
@testable import ProviderKit

@Suite struct InMemoryKeyStoreTests {
    @Test func roundtripPerProviderAndProfile() throws {
        let store = InMemoryKeyStore()
        try store.setKey("sk-ant-1", provider: .anthropic, profile: "private")
        try store.setKey("sk-or-2", provider: .openrouter, profile: "business")

        #expect(try store.key(provider: .anthropic, profile: "private") == "sk-ant-1")
        #expect(try store.key(provider: .openrouter, profile: "business") == "sk-or-2")
        // Same provider, different billing profile: strictly separated.
        #expect(try store.key(provider: .anthropic, profile: "business") == nil)
    }

    @Test func overwriteAndDelete() throws {
        let store = InMemoryKeyStore()
        try store.setKey("old", provider: .openai, profile: "default")
        try store.setKey("new", provider: .openai, profile: "default")
        #expect(try store.key(provider: .openai, profile: "default") == "new")

        try store.deleteKey(provider: .openai, profile: "default")
        #expect(try store.key(provider: .openai, profile: "default") == nil)
        // Deleting a missing key is not an error.
        try store.deleteKey(provider: .openai, profile: "default")
    }
}

@Suite struct OAuthFeatureFlagTests {
    @Test func openAIDefaultsToAPIKeyWhenFlagOff() {
        OAuthFeature.isEnabled = false
        #expect(.openai.authMethod == .apiKey)
        #expect(.openai.supportsOAuth == false)
        #expect(.openai.hasOAuthConfig == true)
    }

    @Test func googleDefaultsToAPIKeyWhenFlagOff() {
        OAuthFeature.isEnabled = false
        #expect(.google.authMethod == .apiKey)
        #expect(.google.supportsOAuth == false)
        #expect(.google.hasOAuthConfig == true)
    }

    @Test func anthropicAlwaysUsesAPIKey() {
        OAuthFeature.isEnabled = false
        #expect(.anthropic.authMethod == .apiKey)
        #expect(.anthropic.supportsOAuth == false)
        #expect(.anthropic.hasOAuthConfig == false)
    }

    @Test func openAIUsesOAuthWhenFlagOn() {
        OAuthFeature.isEnabled = true
        defer { OAuthFeature.isEnabled = false }

        if case .oauth(let config) = .openai.authMethod {
            #expect(config.clientId == "symaira-terminal")
        } else {
            Issue.record("Expected .oauth when flag is on")
        }
        #expect(.openai.supportsOAuth == true)
    }

    @Test func googleUsesOAuthWhenFlagOn() {
        OAuthFeature.isEnabled = true
        defer { OAuthFeature.isEnabled = false }

        if case .oauth(let config) = .google.authMethod {
            #expect(config.clientId == "symaira-terminal")
        } else {
            Issue.record("Expected .oauth when flag is on")
        }
        #expect(.google.supportsOAuth == true)
    }
}
