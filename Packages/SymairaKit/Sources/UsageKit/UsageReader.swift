import Foundation

/// The single seam every concrete data source implements — local file readers,
/// quota fetchers, and any future remote sources all conform to this protocol.
public protocol UsageReader: Sendable {
    var provider: UsageProvider { get }

    /// Read all samples since `date`. Implementations should be idempotent and
    /// return empty when no data is available (e.g. agent not installed).
    func read(since date: Date) async throws -> [UsageSample]
}

/// A reader that always returns an empty result set. Useful as a placeholder
/// and in tests that need a registry with no real I/O.
public struct NullUsageReader: UsageReader {
    public let provider: UsageProvider

    public init(provider: UsageProvider) {
        self.provider = provider
    }

    public func read(since date: Date) async throws -> [UsageSample] { [] }
}
