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

@Suite(.serialized) struct OAuthFeatureFlagTests {
    @Test func openAIDefaultsToAPIKeyWhenFlagOff() {
        OAuthFeature.isEnabled = false
        #expect(ProviderID.openai.authMethod == .apiKey)
        #expect(ProviderID.openai.supportsOAuth == false)
        #expect(ProviderID.openai.hasOAuthConfig == true)
    }

    @Test func googleDefaultsToAPIKeyWhenFlagOff() {
        OAuthFeature.isEnabled = false
        #expect(ProviderID.google.authMethod == .apiKey)
        #expect(ProviderID.google.supportsOAuth == false)
        #expect(ProviderID.google.hasOAuthConfig == true)
    }

    @Test func anthropicAlwaysUsesAPIKey() {
        OAuthFeature.isEnabled = false
        #expect(ProviderID.anthropic.authMethod == .apiKey)
        #expect(ProviderID.anthropic.supportsOAuth == false)
        #expect(ProviderID.anthropic.hasOAuthConfig == false)
    }

    @Test func openAIUsesOAuthWhenFlagOn() {
        OAuthFeature.isEnabled = true
        defer { OAuthFeature.isEnabled = false }

        if case .oauth(let config) = ProviderID.openai.authMethod {
            #expect(config.clientId == "symaira-terminal")
        } else {
            Issue.record("Expected .oauth when flag is on")
        }
        #expect(ProviderID.openai.supportsOAuth == true)
    }

    @Test func googleUsesOAuthWhenFlagOn() {
        OAuthFeature.isEnabled = true
        defer { OAuthFeature.isEnabled = false }

        if case .oauth(let config) = ProviderID.google.authMethod {
            #expect(config.clientId == "symaira-terminal")
        } else {
            Issue.record("Expected .oauth when flag is on")
        }
        #expect(ProviderID.google.supportsOAuth == true)
    }
}
