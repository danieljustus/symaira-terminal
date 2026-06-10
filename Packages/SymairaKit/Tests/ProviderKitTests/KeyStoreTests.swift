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
