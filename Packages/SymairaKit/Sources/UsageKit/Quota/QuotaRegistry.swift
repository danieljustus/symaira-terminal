import Foundation

/// Aggregates quota snapshots from all enabled fetchers.
///
/// Fetchers that are disabled or that fail degrade gracefully — their errors are
/// captured and exposed via `errors`, never propagated as throws. The local-file
/// usage path (UsageRegistry) is completely independent and unaffected.
public struct QuotaRegistry: Sendable {
    private let fetchers: [any QuotaFetcher]

    public init(fetchers: [any QuotaFetcher]) {
        self.fetchers = fetchers
    }

    public struct QuotaResult: Sendable {
        public let quotas: [UsageQuota]
        public let errors: [UsageProvider: QuotaFetchError]

        public init(quotas: [UsageQuota], errors: [UsageProvider: QuotaFetchError]) {
            self.quotas = quotas
            self.errors = errors
        }
    }

    /// Concurrently fetch all enabled fetchers. Disabled or failed fetchers
    /// appear in `errors`; the rest are in `quotas`.
    public func fetchAll() async -> QuotaResult {
        await withTaskGroup(of: (UsageProvider, Result<[UsageQuota], QuotaFetchError>).self) { group in
            for fetcher in fetchers {
                group.addTask {
                    do {
                        let q = try await fetcher.fetchQuota()
                        return (fetcher.provider, .success(q))
                    } catch let e as QuotaFetchError {
                        return (fetcher.provider, .failure(e))
                    } catch {
                        return (fetcher.provider, .failure(.unexpectedResponse(error.localizedDescription)))
                    }
                }
            }
            var quotas: [UsageQuota] = []
            var errors: [UsageProvider: QuotaFetchError] = [:]
            for await (provider, result) in group {
                switch result {
                case .success(let q): quotas.append(contentsOf: q)
                case .failure(let e):
                    if case .notEnabled = e { break }  // not an error, just disabled
                    errors[provider] = e
                }
            }
            return QuotaResult(quotas: quotas, errors: errors)
        }
    }
}
