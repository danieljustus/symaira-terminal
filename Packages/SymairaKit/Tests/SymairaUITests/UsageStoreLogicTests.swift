import Foundation
import Testing
import UsageKit
@testable import SymairaUI

// MARK: - TimeBucket

@Suite struct TimeBucketTests {
    @Test func rawValuesMatchUIStrings() {
        #expect(TimeBucket.today.rawValue == "Today")
        #expect(TimeBucket.week.rawValue == "This Week")
        #expect(TimeBucket.month.rawValue == "This Month")
        #expect(TimeBucket.allCases.count == 3)
    }

    @Test func todayStartsAtStartOfDay() {
        let now = Date()
        let expected = Calendar.current.startOfDay(for: now)
        #expect(TimeBucket.today.startDate == expected)
    }

    @Test func monthStartsAtFirstOfMonth() {
        let now = Date()
        let expected = Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: now)
        )
        #expect(TimeBucket.month.startDate == expected)
    }

    @Test func bucketsAreChronologicallyOrdered() {
        // today ⊂ week ⊂ month — earlier buckets must never start later.
        #expect(TimeBucket.today.startDate >= TimeBucket.week.startDate)
        #expect(TimeBucket.week.startDate >= TimeBucket.month.startDate)
    }
}

// MARK: - UsageStore observable state

@Suite @MainActor struct UsageStoreStateTests {
    private func makeStore() -> UsageStore {
        UsageStore(
            registry: UsageRegistry(readers: []),
            quotaRegistry: QuotaRegistry(fetchers: [])
        )
    }

    private func sample(
        _ id: String,
        provider: UsageProvider,
        timestamp: Date,
        input: Int = 100,
        output: Int = 50
    ) -> UsageSample {
        UsageSample(
            id: id,
            provider: provider,
            modelID: "test-model",
            timestamp: timestamp,
            inputTokens: input,
            outputTokens: output
        )
    }

    // MARK: - Bucket totals

    @Test func todayTotalsIncludeOnlyTodaySamples() {
        let store = makeStore()
        let now = Date()
        let todayStart = TimeBucket.today.startDate
        store.snapshot = UsageSnapshot(samples: [
            sample("in-today", provider: UsageProviders.claudeCode, timestamp: todayStart.addingTimeInterval(1)),
            sample("before-today", provider: UsageProviders.claudeCode, timestamp: todayStart.addingTimeInterval(-1)),
        ], generatedAt: now)
        store.selectedBucket = .today

        let totals = store.totalsForSelectedBucket
        #expect(totals.sampleCount == 1)
        #expect(totals.inputTokens == 100)
        #expect(totals.outputTokens == 50)
        #expect(totals.totalTokens == 150)
    }

    @Test func weekTotalsRespectWeekBoundary() {
        let store = makeStore()
        let now = Date()
        let weekStart = TimeBucket.week.startDate
        store.snapshot = UsageSnapshot(samples: [
            sample("in-week", provider: UsageProviders.claudeCode, timestamp: weekStart.addingTimeInterval(1)),
            sample("before-week", provider: UsageProviders.claudeCode, timestamp: weekStart.addingTimeInterval(-1)),
        ], generatedAt: now)
        store.selectedBucket = .week

        #expect(store.totalsForSelectedBucket.sampleCount == 1)
    }

    @Test func monthTotalsRespectMonthBoundary() {
        let store = makeStore()
        let now = Date()
        let monthStart = TimeBucket.month.startDate
        store.snapshot = UsageSnapshot(samples: [
            sample("in-month", provider: UsageProviders.claudeCode, timestamp: monthStart.addingTimeInterval(1)),
            sample("before-month", provider: UsageProviders.claudeCode, timestamp: monthStart.addingTimeInterval(-1)),
        ], generatedAt: now)
        store.selectedBucket = .month

        #expect(store.totalsForSelectedBucket.sampleCount == 1)
    }

    // MARK: - Provider breakdown

    @Test func byProviderTotalsGroupAndSum() {
        let store = makeStore()
        let now = Date()
        store.snapshot = UsageSnapshot(samples: [
            sample("c1", provider: UsageProviders.claudeCode, timestamp: now, input: 100, output: 10),
            sample("c2", provider: UsageProviders.claudeCode, timestamp: now, input: 200, output: 20),
            sample("x1", provider: UsageProviders.codex, timestamp: now, input: 5, output: 5),
        ], generatedAt: now)
        store.selectedBucket = .today

        let totals = store.byProviderTotals
        #expect(totals[UsageProviders.claudeCode]?.sampleCount == 2)
        #expect(totals[UsageProviders.claudeCode]?.inputTokens == 300)
        #expect(totals[UsageProviders.codex]?.sampleCount == 1)
        #expect(totals[UsageProviders.claudeCode]?.totalTokens == 330)
    }

    // MARK: - Billing window

    @Test func billingWindowContainsRecentSamples() {
        let store = makeStore()
        let now = Date()
        store.snapshot = UsageSnapshot(samples: [
            sample("recent", provider: UsageProviders.claudeCode, timestamp: now),
        ], generatedAt: now)

        let window = store.currentBillingWindow
        #expect(window.totals.sampleCount == 1)
        #expect(window.isActive(at: now))
        #expect(window.remaining(at: now) > 0)
    }

    // MARK: - Refresh lifecycle

    @Test func refreshWithEmptyRegistryYieldsEmptyState() async {
        let store = makeStore()
        await store.refresh()
        #expect(store.snapshot.samples.isEmpty)
        #expect(store.quotaResult.quotas.isEmpty)
        #expect(store.quotaResult.errors.isEmpty)
        #expect(store.error == nil)
        #expect(!store.isRefreshing)
        #expect(store.lastRefreshDate != nil)
    }

    @Test func refreshSkipsQuotaWhenThrottled() async {
        let store = makeStore()
        var quotaCalls = 0
        store.shouldRefreshQuota = { false }
        store.didRefreshQuota = { quotaCalls += 1 }

        await store.refresh()
        #expect(quotaCalls == 0)
        #expect(store.quotaResult.quotas.isEmpty)
    }

    @Test func refreshRunsQuotaWhenAllowed() async {
        let store = makeStore()
        var quotaCalls = 0
        store.shouldRefreshQuota = { true }
        store.didRefreshQuota = { quotaCalls += 1 }

        await store.refresh()
        #expect(quotaCalls == 1)
        #expect(store.quotaResult.quotas.isEmpty)
    }

    @Test func concurrentRefreshIsGuarded() async {
        let store = makeStore()
        async let first: Void = store.refresh()
        async let second: Void = store.refresh()
        _ = await (first, second)
        // Both calls must complete without corrupting state.
        #expect(store.snapshot.samples.isEmpty)
        #expect(!store.isRefreshing)
    }
}
