import Foundation

/// Immutable aggregate of usage samples, the output of a `UsageRegistry` read cycle.
public struct UsageSnapshot: Equatable, Sendable {
    public let samples: [UsageSample]
    public let generatedAt: Date

    public init(samples: [UsageSample], generatedAt: Date) {
        self.samples = samples
        self.generatedAt = generatedAt
    }

    // MARK: - Convenience totals

    public var totalInputTokens: Int { samples.reduce(0) { $0 + $1.inputTokens } }
    public var totalOutputTokens: Int { samples.reduce(0) { $0 + $1.outputTokens } }
    public var totalCacheCreationTokens: Int { samples.reduce(0) { $0 + $1.cacheCreationTokens } }
    public var totalCacheReadTokens: Int { samples.reduce(0) { $0 + $1.cacheReadTokens } }
    public var totalTokens: Int { samples.reduce(0) { $0 + $1.totalTokens } }
    public var totalCostUSD: Decimal? {
        let costs = samples.compactMap(\.costUSD)
        guard !costs.isEmpty else { return nil }
        return costs.reduce(.zero, +)
    }

    // MARK: - Filtering

    public func filtered(by provider: UsageProvider) -> UsageSnapshot {
        UsageSnapshot(
            samples: samples.filter { $0.provider == provider },
            generatedAt: generatedAt
        )
    }

    public func filtered(after date: Date) -> UsageSnapshot {
        UsageSnapshot(
            samples: samples.filter { $0.timestamp >= date },
            generatedAt: generatedAt
        )
    }

    public func filtered(by model: String) -> UsageSnapshot {
        UsageSnapshot(
            samples: samples.filter { $0.modelID == model },
            generatedAt: generatedAt
        )
    }

    // MARK: - Breakdown helpers

    public var byProvider: [UsageProvider: UsageSnapshot] {
        Dictionary(grouping: samples, by: \.provider)
            .mapValues { UsageSnapshot(samples: $0, generatedAt: generatedAt) }
    }

    public var byModel: [String: UsageSnapshot] {
        Dictionary(grouping: samples, by: \.modelID)
            .mapValues { UsageSnapshot(samples: $0, generatedAt: generatedAt) }
    }

    public var byProject: [String: UsageSnapshot] {
        Dictionary(grouping: samples.filter { $0.project != nil }, by: { $0.project! })
            .mapValues { UsageSnapshot(samples: $0, generatedAt: generatedAt) }
    }
}
