import Foundation
import ProviderKit
import TerminalCore

public struct FixErrorService: Sendable {
    private let client: ProviderChatClient
    private let redactor: SecretRedactor

    public init(keyStore: KeyStore = KeychainKeyStore(), redactor: SecretRedactor = SecretRedactor()) {
        self.client = ProviderChatClient(keyStore: keyStore)
        self.redactor = redactor
    }

    public func prepareOutput(_ commandOutput: String) -> RedactionResult {
        redactor.redact(commandOutput)
    }

    public func buildPrompt(commandOutput: String, provider: ProviderID, profile: String) async throws -> String? {
        let redacted = redactor.redact(commandOutput)

        let systemPrompt = """
        You are a helpful assistant that analyzes command errors and suggests fixes.
        Given the command output below, identify the error and suggest a fix.
        Be concise and provide actionable steps.

        Command output:
        \(redacted.displayText)
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
