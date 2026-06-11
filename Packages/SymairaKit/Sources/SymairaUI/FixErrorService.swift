import Foundation
import ProviderKit

public struct FixErrorService: Sendable {
    private let client: ProviderChatClient

    public init(keyStore: KeyStore = KeychainKeyStore()) {
        self.client = ProviderChatClient(keyStore: keyStore)
    }

    public func buildPrompt(commandOutput: String, provider: ProviderID, profile: String) async throws -> String? {
        let systemPrompt = """
        You are a helpful assistant that analyzes command errors and suggests fixes.
        Given the command output below, identify the error and suggest a fix.
        Be concise and provide actionable steps.

        Command output:
        \(commandOutput)
        """

        return try await client.complete(
            system: systemPrompt,
            user: "Analyze this error and suggest a fix:",
            provider: provider,
            profile: profile,
            maxTokens: 1024
        )
    }
}
