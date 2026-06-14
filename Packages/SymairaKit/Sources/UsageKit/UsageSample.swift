import Foundation

/// A single recorded usage event from one agent invocation or API call.
public struct UsageSample: Equatable, Sendable, Codable, Identifiable {
    /// Stable dedup key: prefer a message/request id from the source, fall back to a generated UUID.
    public let id: String
    public let provider: UsageProvider
    /// Model identifier as reported by the source (e.g. "claude-opus-4-5").
    public let modelID: String
    public let timestamp: Date
    public let inputTokens: Int
    public let outputTokens: Int
    /// Tokens written to the prompt cache.
    public let cacheCreationTokens: Int
    /// Tokens read back from the prompt cache.
    public let cacheReadTokens: Int
    /// USD cost, if already computed (e.g. from a pricing layer). Nil = tokens-only.
    public let costUSD: Decimal?
    /// Path of the source file this sample was parsed from (for incremental refresh).
    public let sourcePath: String?
    /// Optional project/workspace name, when the source records it.
    public let project: String?

    public var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    public init(
        id: String,
        provider: UsageProvider,
        modelID: String,
        timestamp: Date,
        inputTokens: Int,
        outputTokens: Int,
        cacheCreationTokens: Int = 0,
        cacheReadTokens: Int = 0,
        costUSD: Decimal? = nil,
        sourcePath: String? = nil,
        project: String? = nil
    ) {
        self.id = id
        self.provider = provider
        self.modelID = modelID
        self.timestamp = timestamp
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
        self.costUSD = costUSD
        self.sourcePath = sourcePath
        self.project = project
    }
}
