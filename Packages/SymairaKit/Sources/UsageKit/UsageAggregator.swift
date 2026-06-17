import Foundation

/// Aggregated totals for a time bucket or grouping.
public struct UsageTotals: Equatable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheCreationTokens: Int
    public let cacheReadTokens: Int
    public let costUSD: Decimal?
    public let sampleCount: Int

    public var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    public init(
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheCreationTokens: Int = 0,
        cacheReadTokens: Int = 0,
        costUSD: Decimal? = nil,
        sampleCount: Int = 0
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
        self.costUSD = costUSD
        self.sampleCount = sampleCount
    }

    public static func sum(_ totals: [UsageTotals]) -> UsageTotals {
        let costs = totals.compactMap(\.costUSD)
        return UsageTotals(
            inputTokens: totals.reduce(0) { $0 + $1.inputTokens },
            outputTokens: totals.reduce(0) { $0 + $1.outputTokens },
            cacheCreationTokens: totals.reduce(0) { $0 + $1.cacheCreationTokens },
            cacheReadTokens: totals.reduce(0) { $0 + $1.cacheReadTokens },
            costUSD: costs.isEmpty ? nil : costs.reduce(.zero, +),
            sampleCount: totals.reduce(0) { $0 + $1.sampleCount }
        )
    }
}

/// A Claude-style rolling billing window.
///
/// Anthropic Pro/Max plans reset on a 5-hour rolling basis. `BillingWindow`
/// represents the current window: when it started, when it ends, and how
/// much has been used in it.
public struct BillingWindow: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let totals: UsageTotals

    public var remaining: TimeInterval { max(0, end.timeIntervalSinceNow) }
    public var isActive: Bool { isActive(at: Date()) }

    public func remaining(at now: Date) -> TimeInterval { max(0, end.timeIntervalSince(now)) }
    public func isActive(at now: Date) -> Bool { now < end }

    public init(start: Date, end: Date, totals: UsageTotals) {
        self.start = start
        self.end = end
        self.totals = totals
    }
}

/// Aggregates `UsageSample`s into standard time buckets and 5-hour billing windows.
///
/// All boundary computations are timezone-correct. Inject `clock` in tests to
/// control "now" deterministically.
public struct UsageAggregator: Sendable {
    public let pricing: PricingTable
    public let calendar: Calendar
    public let billingWindowDuration: TimeInterval

    public init(
        pricing: PricingTable = .bundled,
        calendar: Calendar = .current,
        billingWindowDuration: TimeInterval = 5 * 60 * 60
    ) {
        self.pricing = pricing
        self.calendar = calendar
        self.billingWindowDuration = billingWindowDuration
    }

    // MARK: - Time Bucket Aggregation

    public func today(samples: [UsageSample], now: Date) -> UsageTotals {
        let start = calendar.startOfDay(for: now)
        return totals(samples: samples.filter { $0.timestamp >= start })
    }

    public func thisWeek(samples: [UsageSample], now: Date) -> UsageTotals {
        guard let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) else {
            return totals(samples: [])
        }
        return totals(samples: samples.filter { $0.timestamp >= start })
    }

    public func thisMonth(samples: [UsageSample], now: Date) -> UsageTotals {
        guard let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else {
            return totals(samples: [])
        }
        return totals(samples: samples.filter { $0.timestamp >= start })
    }

    /// Per-day rollup for the N most recent calendar days including today.
    public func daily(samples: [UsageSample], now: Date, days: Int = 30) -> [(date: Date, totals: UsageTotals)] {
        var result: [(date: Date, totals: UsageTotals)] = []
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: now)),
                  let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
            let bucket = samples.filter { $0.timestamp >= day && $0.timestamp < nextDay }
            result.append((date: day, totals: totals(samples: bucket)))
        }
        return result.reversed()
    }

    // MARK: - Per-Provider / Per-Model Breakdowns

    public func byProvider(samples: [UsageSample]) -> [UsageProvider: UsageTotals] {
        Dictionary(grouping: samples, by: \.provider)
            .mapValues { totals(samples: $0) }
    }

    public func byModel(samples: [UsageSample]) -> [String: UsageTotals] {
        Dictionary(grouping: samples, by: \.modelID)
            .mapValues { totals(samples: $0) }
    }

    public func byProject(samples: [UsageSample]) -> [String: UsageTotals] {
        Dictionary(grouping: samples.filter { $0.project != nil }, by: { $0.project! })
            .mapValues { totals(samples: $0) }
    }

    // MARK: - 5-Hour Billing Windows

    /// Returns all billing windows that contain at least one sample, plus the
    /// current open window (even if empty) anchored to `windowStart`.
    ///
    /// `windowStart` is the reference epoch for window alignment. For Claude Pro/Max,
    /// each window begins at the time of the first message in that session block;
    /// here we align to the provided anchor so callers can pass the user's known
    /// subscription-reset time or just `Date.distantPast` for a simple rolling window.
    public func billingWindows(
        samples: [UsageSample],
        now: Date,
        windowStart: Date
    ) -> [BillingWindow] {
        var windows: [BillingWindow] = []
        var cursor = windowStart

        // Advance cursor past windows before any sample.
        if let firstSample = samples.map(\.timestamp).min() {
            while cursor.addingTimeInterval(billingWindowDuration) < firstSample {
                cursor = cursor.addingTimeInterval(billingWindowDuration)
            }
        }

        // Build windows up to and including the current one.
        while cursor <= now {
            let end = cursor.addingTimeInterval(billingWindowDuration)
            let bucket = samples.filter { $0.timestamp >= cursor && $0.timestamp < end }
            if !bucket.isEmpty || (cursor <= now && end > now) {
                windows.append(BillingWindow(start: cursor, end: end, totals: totals(samples: bucket)))
            }
            cursor = end
        }
        return windows
    }

    /// The single currently-active 5-hour billing window for `now`.
    public func currentBillingWindow(
        samples: [UsageSample],
        now: Date,
        windowStart: Date
    ) -> BillingWindow {
        let all = billingWindows(samples: samples, now: now, windowStart: windowStart)
        return all.last ?? BillingWindow(
            start: now,
            end: now.addingTimeInterval(billingWindowDuration),
            totals: UsageTotals()
        )
    }

    // MARK: - Helpers

    private func totals(samples: [UsageSample]) -> UsageTotals {
        let costs = samples.compactMap { pricing.cost(for: $0) }
        return UsageTotals(
            inputTokens: samples.reduce(0) { $0 + $1.inputTokens },
            outputTokens: samples.reduce(0) { $0 + $1.outputTokens },
            cacheCreationTokens: samples.reduce(0) { $0 + $1.cacheCreationTokens },
            cacheReadTokens: samples.reduce(0) { $0 + $1.cacheReadTokens },
            costUSD: costs.isEmpty ? nil : costs.reduce(.zero, +),
            sampleCount: samples.count
        )
    }
}
