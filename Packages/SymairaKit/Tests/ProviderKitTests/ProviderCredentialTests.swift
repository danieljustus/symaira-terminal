import Testing
@testable import ProviderKit

// MARK: - ProviderCredential Tests

@Suite struct ProviderCredentialTests {
    @Test func apiKeyCredentialValue() {
        let credential = ProviderCredential.apiKey(Secret("sk-ant-123"))
        #expect(credential.secretValue == "sk-ant-123")
        #expect(!credential.isEmpty)
    }

    @Test func oauthBearerCredentialValue() {
        let credential = ProviderCredential.oauthBearer(Secret("tok_abc"))
        #expect(credential.secretValue == "tok_abc")
        #expect(!credential.isEmpty)
    }

    @Test func noneCredentialIsEmpty() {
        let credential = ProviderCredential.none
        #expect(credential.secretValue == nil)
        #expect(credential.isEmpty)
    }

    @Test func emptyApiKeyCredentialIsEmpty() {
        let credential = ProviderCredential.apiKey(Secret(""))
        #expect(credential.isEmpty)
    }

    @Test func emptyOAuthBearerCredentialIsEmpty() {
        let credential = ProviderCredential.oauthBearer(Secret(""))
        #expect(credential.isEmpty)
    }
}

// MARK: - supportedAuthModes Tests

@Suite struct SupportedAuthModesTests {
    @Test func anthropicSupportsAPIKeyOnly() {
        #expect(ProviderID.anthropic.supportedAuthModes.count == 1)
        if case .apiKey = ProviderID.anthropic.supportedAuthModes.first {} else {
            Issue.record("Anthropic should support .apiKey")
        }
        #expect(!ProviderID.anthropic.supportsOAuth)
        #expect(ProviderID.anthropic.supportsAPIKey)
        #expect(!ProviderID.anthropic.hasOAuthConfig)
    }

    @Test func openrouterSupportsAPIKeyOnly() {
        #expect(ProviderID.openrouter.supportedAuthModes.count == 1)
        if case .apiKey = ProviderID.openrouter.supportedAuthModes.first {} else {
            Issue.record("OpenRouter should support .apiKey")
        }
        #expect(!ProviderID.openrouter.supportsOAuth)
        #expect(ProviderID.openrouter.supportsAPIKey)
        #expect(!ProviderID.openrouter.hasOAuthConfig)
    }

    @Test func ollamaSupportsAPIKeyOnly() {
        #expect(ProviderID.ollama.supportedAuthModes.count == 1)
        if case .apiKey = ProviderID.ollama.supportedAuthModes.first {} else {
            Issue.record("Ollama should support .apiKey")
        }
        #expect(!ProviderID.ollama.supportsOAuth)
        #expect(ProviderID.ollama.supportsAPIKey)
        #expect(!ProviderID.ollama.hasOAuthConfig)
    }

    @Test func openAICompatibleSupportsAPIKeyOnly() {
        #expect(ProviderID.openAICompatible.supportedAuthModes.count == 1)
        if case .apiKey = ProviderID.openAICompatible.supportedAuthModes.first {} else {
            Issue.record("OpenAI Compatible should support .apiKey")
        }
        #expect(!ProviderID.openAICompatible.supportsOAuth)
        #expect(ProviderID.openAICompatible.supportsAPIKey)
        #expect(!ProviderID.openAICompatible.hasOAuthConfig)
    }

    @Test func openAISupportsAPIKeyAndOAuth() {
        #expect(ProviderID.openai.supportedAuthModes.count == 2)
        #expect(ProviderID.openai.supportsAPIKey)
        #expect(ProviderID.openai.hasOAuthConfig)
        #expect(ProviderID.openai.oauthConfig != nil)
    }

    @Test func googleSupportsAPIKeyAndOAuth() {
        #expect(ProviderID.google.supportedAuthModes.count == 2)
        #expect(ProviderID.google.supportsAPIKey)
        #expect(ProviderID.google.hasOAuthConfig)
        #expect(ProviderID.google.oauthConfig != nil)
    }

    @Test func authMethodDerivesFromSupportedModes() {
        for provider in ProviderID.allCases {
            let modes = provider.supportedAuthModes
            let method = provider.authMethod
            #expect(modes.contains(method))
        }
    }
}

// MARK: - resolveCredential Tests

@Suite struct ResolveCredentialTests {
    @Test func anthropicResolvesAPIKey() async throws {
        let keyStore = InMemoryKeyStore()
        let tokenStore = InMemoryTokenStore()
        let client = ProviderChatClient(keyStore: keyStore, tokenStore: tokenStore)

        try keyStore.setKey("sk-ant-test", provider: .anthropic, profile: "default")
        let credential = try await client.resolveCredential(provider: .anthropic, profile: "default")

        if case .apiKey(let secret) = credential {
            #expect(secret.value == "sk-ant-test")
        } else {
            Issue.record("Expected .apiKey credential for Anthropic")
        }
    }

    @Test func openrouterResolvesAPIKey() async throws {
        let keyStore = InMemoryKeyStore()
        let tokenStore = InMemoryTokenStore()
        let client = ProviderChatClient(keyStore: keyStore, tokenStore: tokenStore)

        try keyStore.setKey("sk-or-test", provider: .openrouter, profile: "default")
        let credential = try await client.resolveCredential(provider: .openrouter, profile: "default")

        if case .apiKey(let secret) = credential {
            #expect(secret.value == "sk-or-test")
        } else {
            Issue.record("Expected .apiKey credential for OpenRouter")
        }
    }

    @Test func ollamaResolvesNone() async throws {
        let keyStore = InMemoryKeyStore()
        let tokenStore = InMemoryTokenStore()
        let client = ProviderChatClient(keyStore: keyStore, tokenStore: tokenStore)

        let credential = try await client.resolveCredential(provider: .ollama, profile: "default")
        #expect(credential == .none)
    }

    @Test func openAICompatibleResolvesAPIKey() async throws {
        let keyStore = InMemoryKeyStore()
        let tokenStore = InMemoryTokenStore()
        let client = ProviderChatClient(keyStore: keyStore, tokenStore: tokenStore)

        try keyStore.setKey("sk-compat-test", provider: .openAICompatible, profile: "default")
        let credential = try await client.resolveCredential(provider: .openAICompatible, profile: "default")

        if case .apiKey(let secret) = credential {
            #expect(secret.value == "sk-compat-test")
        } else {
            Issue.record("Expected .apiKey credential for OpenAI Compatible")
        }
    }

    @Test func openAIResolvesEmptyKeyWhenNoKeyStored() async throws {
        let keyStore = InMemoryKeyStore()
        let tokenStore = InMemoryTokenStore()
        let client = ProviderChatClient(keyStore: keyStore, tokenStore: tokenStore)

        let credential = try await client.resolveCredential(provider: .openai, profile: "default")
        if case .apiKey(let secret) = credential {
            #expect(secret.value.isEmpty)
        } else {
            Issue.record("Expected .apiKey credential (empty) for OpenAI without stored key")
        }
    }

    @Test func googleResolvesEmptyKeyWhenNoKeyStored() async throws {
        let keyStore = InMemoryKeyStore()
        let tokenStore = InMemoryTokenStore()
        let client = ProviderChatClient(keyStore: keyStore, tokenStore: tokenStore)

        let credential = try await client.resolveCredential(provider: .google, profile: "default")
        if case .apiKey(let secret) = credential {
            #expect(secret.value.isEmpty)
        } else {
            Issue.record("Expected .apiKey credential (empty) for Google without stored key")
        }
    }

    @Test func missingAPIKeyReturnsEmptyCredential() async throws {
        let keyStore = InMemoryKeyStore()
        let tokenStore = InMemoryTokenStore()
        let client = ProviderChatClient(keyStore: keyStore, tokenStore: tokenStore)

        let credential = try await client.resolveCredential(provider: .anthropic, profile: "default")
        if case .apiKey(let secret) = credential {
            #expect(secret.value.isEmpty)
        } else {
            Issue.record("Expected .apiKey credential (empty) for Anthropic without stored key")
        }
    }
}
