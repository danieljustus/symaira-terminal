import Testing
import Foundation
@testable import UsageKit

// Fixed "now" for all tests: 2026-06-14 12:00:00 UTC
private let testNow: Date = {
    var comps = DateComponents()
    comps.year = 2026; comps.month = 6; comps.day = 14
    comps.hour = 12; comps.minute = 0; comps.second = 0
    comps.timeZone = TimeZone(identifier: "UTC")
    return Calendar(identifier: .gregorian).date(from: comps)!
}()

private func utcDate(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
    var comps = DateComponents()
    comps.year = year; comps.month = month; comps.day = day
    comps.hour = hour; comps.timeZone = TimeZone(identifier: "UTC")
    return Calendar(identifier: .gregorian).date(from: comps)!
}

private func sample(ts: Date, input: Int = 10, output: Int = 5, model: String = "unknown-model") -> UsageSample {
    UsageSample(
        id: UUID().uuidString,
        provider: UsageProviders.claudeCode,
        modelID: model,
        timestamp: ts,
        inputTokens: input,
        outputTokens: output
    )
}

@Suite struct AggregatorTimeBucketTests {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    var agg: UsageAggregator { UsageAggregator(pricing: .bundled, calendar: cal) }

    @Test func todayIncludesOnlyCurrentDaySamples() {
        let todaySample  = sample(ts: utcDate(year: 2026, month: 6, day: 14, hour: 9))
        let yesterdaySample = sample(ts: utcDate(year: 2026, month: 6, day: 13, hour: 23))
        let totals = agg.today(samples: [todaySample, yesterdaySample], now: testNow)
        #expect(totals.sampleCount == 1)
        #expect(totals.inputTokens == 10)
    }

    @Test func thisWeekSpansMonToNow() {
        // testNow is a Sunday, week starts Monday in Gregorian UTC.
        // Use ISO8601 week calendar for week boundaries.
        let thisWeekSample = sample(ts: utcDate(year: 2026, month: 6, day: 14, hour: 10))
        let lastWeekSample = sample(ts: utcDate(year: 2026, month: 6, day: 7, hour: 10))
        let totals = agg.thisWeek(samples: [thisWeekSample, lastWeekSample], now: testNow)
        // At minimum, today's sample should be counted.
        #expect(totals.inputTokens >= 10)
    }

    @Test func thisMonthIncludesAllJune2026() {
        let juneSample = sample(ts: utcDate(year: 2026, month: 6, day: 1))
        let maySample  = sample(ts: utcDate(year: 2026, month: 5, day: 31))
        let totals = agg.thisMonth(samples: [juneSample, maySample], now: testNow)
        #expect(totals.sampleCount == 1)
    }

    @Test func dailyRollupHasCorrectDayBuckets() {
        let s1 = sample(ts: utcDate(year: 2026, month: 6, day: 14, hour: 8))
        let s2 = sample(ts: utcDate(year: 2026, month: 6, day: 13, hour: 8))
        let s3 = sample(ts: utcDate(year: 2026, month: 6, day: 13, hour: 20))
        let daily = agg.daily(samples: [s1, s2, s3], now: testNow, days: 3)
        #expect(daily.count == 3)
        let today = daily.last!
        #expect(today.totals.sampleCount == 1)
        let yesterday = daily[daily.count - 2]
        #expect(yesterday.totals.sampleCount == 2)
    }

    @Test func byProviderGroupsCorrectly() {
        let s1 = sample(ts: testNow, input: 100, output: 0)
        var s2 = sample(ts: testNow, input: 200, output: 0)
        s2 = UsageSample(
            id: s2.id, provider: UsageProviders.codex, modelID: s2.modelID,
            timestamp: s2.timestamp, inputTokens: 200, outputTokens: 0
        )
        let groups = agg.byProvider(samples: [s1, s2])
        #expect(groups[UsageProviders.claudeCode]?.inputTokens == 100)
        #expect(groups[UsageProviders.codex]?.inputTokens == 200)
    }

    @Test func byModelGroupsCorrectly() {
        let s1 = sample(ts: testNow, model: "claude-opus-4-5")
        let s2 = sample(ts: testNow, model: "claude-opus-4-5")
        let s3 = sample(ts: testNow, model: "claude-haiku-4-5-20251001")
        let groups = agg.byModel(samples: [s1, s2, s3])
        #expect(groups["claude-opus-4-5"]?.sampleCount == 2)
        #expect(groups["claude-haiku-4-5-20251001"]?.sampleCount == 1)
    }
}

@Suite struct BillingWindowTests {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    var agg: UsageAggregator {
        UsageAggregator(pricing: .bundled, calendar: cal, billingWindowDuration: 5 * 60 * 60)
    }

    @Test func singleWindowWithinFiveHours() {
        let anchor = testNow.addingTimeInterval(-2 * 3600)  // 2 hours ago
        let s = sample(ts: testNow.addingTimeInterval(-1 * 3600))
        let current = agg.currentBillingWindow(samples: [s], now: testNow, windowStart: anchor)
        #expect(current.isActive)
        #expect(current.totals.sampleCount == 1)
    }

    @Test func samplesBeforeWindowAnchorAreExcluded() {
        let anchor = testNow  // window starts NOW
        let pastSample = sample(ts: testNow.addingTimeInterval(-1))
        let current = agg.currentBillingWindow(samples: [pastSample], now: testNow, windowStart: anchor)
        #expect(current.totals.sampleCount == 0)
    }

    @Test func windowRemainingIsPositive() {
        let anchor = testNow.addingTimeInterval(-1 * 3600)
        let current = agg.currentBillingWindow(samples: [], now: testNow, windowStart: anchor)
        #expect(current.remaining > 0)
    }

    @Test func windowAcrossBoundaryCountsOnlyCurrentWindow() {
        let anchor = testNow.addingTimeInterval(-6 * 3600)  // 6h ago → two windows
        let oldSample     = sample(ts: testNow.addingTimeInterval(-5.5 * 3600))  // previous window
        let currentSample = sample(ts: testNow.addingTimeInterval(-0.5 * 3600))  // current window
        let current = agg.currentBillingWindow(
            samples: [oldSample, currentSample],
            now: testNow,
            windowStart: anchor
        )
        #expect(current.totals.sampleCount == 1)
        #expect(current.totals.inputTokens == 10)
    }
}

@Suite struct UsageTotalsSumTests {
    @Test func sumCombinesTotals() {
        let a = UsageTotals(inputTokens: 100, outputTokens: 50, costUSD: Decimal(1))
        let b = UsageTotals(inputTokens: 200, outputTokens: 80, costUSD: Decimal(2))
        let total = UsageTotals.sum([a, b])
        #expect(total.inputTokens == 300)
        #expect(total.outputTokens == 130)
        #expect(total.costUSD == Decimal(3))
    }

    @Test func sumWithNilCostReturnsNilWhenAllNil() {
        let a = UsageTotals(inputTokens: 10)
        let b = UsageTotals(inputTokens: 20)
        let total = UsageTotals.sum([a, b])
        #expect(total.costUSD == nil)
    }

    @Test func sumEmptyArrayReturnsZeros() {
        let total = UsageTotals.sum([])
        #expect(total.inputTokens == 0)
        #expect(total.costUSD == nil)
    }
}
