import Foundation
import UsageKit

/// MainActor bridge between UsageKit and the SwiftUI views.
///
/// Maintains the latest snapshot and quota results and drives refresh cycles.
/// The store is intentionally thin — all aggregation logic lives in UsageKit.
@MainActor
public final class UsageStore: ObservableObject {
    // MARK: - Published state

    @Published public var snapshot: UsageSnapshot = UsageSnapshot(samples: [], generatedAt: Date())
    @Published public var quotaResult: QuotaRegistry.QuotaResult = .init(quotas: [], errors: [:])
    @Published public var isRefreshing: Bool = false
    @Published public var lastRefreshDate: Date?
    @Published public var selectedBucket: TimeBucket = .today
    @Published public var error: String?

    // MARK: - Aggregation

    public let aggregator: UsageAggregator

    // MARK: - Private

    private let registry: UsageRegistry
    private let quotaRegistry: QuotaRegistry
    private let incrementalCache = IncrementalReadCache()

    /// Called before each quota fetch; return `false` to skip the fetch
    /// (e.g. because `quotaInterval` has not elapsed yet).
    public var shouldRefreshQuota: @MainActor @Sendable () -> Bool = { true }

    /// Called after a quota fetch completes so the caller can record the
    /// timestamp for throttling.
    public var didRefreshQuota: @MainActor @Sendable () -> Void = {}

    public init(
        registry: UsageRegistry = .defaultRegistry,
        quotaRegistry: QuotaRegistry = QuotaRegistry(fetchers: []),
        aggregator: UsageAggregator = UsageAggregator()
    ) {
        self.registry = registry
        self.quotaRegistry = quotaRegistry
        self.aggregator = aggregator
    }

    // MARK: - Computed views

    public var totalsForSelectedBucket: UsageTotals {
        let now = Date()
        switch selectedBucket {
        case .today:   return aggregator.today(samples: snapshot.samples, now: now)
        case .week:    return aggregator.thisWeek(samples: snapshot.samples, now: now)
        case .month:   return aggregator.thisMonth(samples: snapshot.samples, now: now)
        }
    }

    public var byProviderTotals: [UsageProvider: UsageTotals] {
        let filtered = snapshot.filtered(after: selectedBucket.startDate).samples
        return aggregator.byProvider(samples: filtered)
    }

    public var currentBillingWindow: BillingWindow {
        let anchor = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return aggregator.currentBillingWindow(
            samples: snapshot.samples,
            now: Date(),
            windowStart: anchor
        )
    }

    // MARK: - Refresh

    /// Refresh both local-file usage and (if enabled) subscription quotas.
    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        error = nil
        defer { isRefreshing = false; lastRefreshDate = Date() }

        async let snapshotTask = registry.snapshot(since: oneMonthAgo, cache: incrementalCache)

        let newSnapshot = await snapshotTask
        snapshot = newSnapshot

        guard shouldRefreshQuota() else { return }

        async let quotaTask = quotaRegistry.fetchAll()
        let newQuota = await quotaTask
        quotaResult = newQuota
        didRefreshQuota()
    }

    private var oneMonthAgo: Date {
        Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date.distantPast
    }
}

/// Time bucket selection for the usage detail view.
public enum TimeBucket: String, CaseIterable, Sendable {
    case today  = "Today"
    case week   = "This Week"
    case month  = "This Month"

    public var startDate: Date {
        let now = Date()
        switch self {
        case .today:  return Calendar.current.startOfDay(for: now)
        case .week:
            return Calendar.current.date(
                from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            ) ?? now
        case .month:
            return Calendar.current.date(
                from: Calendar.current.dateComponents([.year, .month], from: now)
            ) ?? now
        }
    }
}

extension UsageRegistry {
    /// Default registry with all built-in local readers pre-registered.
    public static let defaultRegistry = UsageRegistry(readers: [
        ClaudeCodeReader(),
        CodexReader(),
        GeminiCLIReader()
    ])
}
