import Foundation
import ProviderKit

public struct NLCommandService: Sendable {
    private let client: ProviderChatClient

    public init(keyStore: KeyStore = KeychainKeyStore()) {
        self.client = ProviderChatClient(keyStore: keyStore)
    }

    public func generateCommand(
        description: String,
        provider: ProviderID,
        profile: String,
        shell: String = "zsh",
        cwd: String = "~"
    ) async throws -> String? {
        let systemPrompt = """
        You are a shell command generator. Convert natural language descriptions into shell commands.
        Output ONLY the command, no explanations. Use \(shell) syntax.
        Current directory: \(cwd)
        OS: macOS
        """

        let result = try await client.complete(
            system: systemPrompt,
            user: description,
            provider: provider,
            profile: profile,
            maxTokens: 256
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
