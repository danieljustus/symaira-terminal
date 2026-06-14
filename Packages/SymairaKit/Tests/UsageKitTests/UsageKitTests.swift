import Testing
import Foundation
@testable import UsageKit

// MARK: - UsageProvider

@Suite struct UsageProviderTests {
    @Test func builtInProvidersHaveUniqueIDs() {
        let ids = UsageProviders.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func providerEquality() {
        let a = UsageProvider(id: "foo", displayName: "Foo")
        let b = UsageProvider(id: "foo", displayName: "Foo")
        #expect(a == b)
    }

    @Test func providerInequality() {
        let a = UsageProvider(id: "foo", displayName: "Foo")
        let b = UsageProvider(id: "bar", displayName: "Bar")
        #expect(a != b)
    }
}

// MARK: - UsageSample

@Suite struct UsageSampleTests {
    @Test func totalTokens() {
        let s = UsageSample(
            id: "s1",
            provider: UsageProviders.claudeCode,
            modelID: "claude-opus-4-5",
            timestamp: Date(),
            inputTokens: 100,
            outputTokens: 200,
            cacheCreationTokens: 50,
            cacheReadTokens: 30
        )
        #expect(s.totalTokens == 380)
    }

    @Test func defaultsAreZero() {
        let s = UsageSample(
            id: "s2",
            provider: UsageProviders.codex,
            modelID: "o4-mini",
            timestamp: Date(),
            inputTokens: 10,
            outputTokens: 20
        )
        #expect(s.cacheCreationTokens == 0)
        #expect(s.cacheReadTokens == 0)
        #expect(s.costUSD == nil)
        #expect(s.sourcePath == nil)
        #expect(s.project == nil)
    }
}

// MARK: - UsageRegistry.merge

@Suite struct UsageRegistryMergeTests {
    let registry = UsageRegistry(readers: [])

    func makeSample(id: String, ts: Date, tokens: Int) -> UsageSample {
        UsageSample(
            id: id,
            provider: UsageProviders.claudeCode,
            modelID: "claude-opus-4-5",
            timestamp: ts,
            inputTokens: tokens,
            outputTokens: 0
        )
    }

    @Test func deduplicatesByID() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let s1 = makeSample(id: "dup", ts: base, tokens: 10)
        let s2 = makeSample(id: "dup", ts: base.addingTimeInterval(1), tokens: 20)
        let result = registry.merge([s1, s2])
        #expect(result.count == 1)
        #expect(result[0].inputTokens == 10) // first occurrence wins
    }

    @Test func sortsByTimestampAscending() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let s1 = makeSample(id: "a", ts: base.addingTimeInterval(2), tokens: 1)
        let s2 = makeSample(id: "b", ts: base, tokens: 2)
        let s3 = makeSample(id: "c", ts: base.addingTimeInterval(1), tokens: 3)
        let result = registry.merge([s1, s2, s3])
        #expect(result.map(\.id) == ["b", "c", "a"])
    }

    @Test func emptyInputReturnsEmpty() {
        #expect(registry.merge([]).isEmpty)
    }
}

// MARK: - UsageSnapshot

@Suite struct UsageSnapshotTests {
    let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    func snap(_ samples: [UsageSample]) -> UsageSnapshot {
        UsageSnapshot(samples: samples, generatedAt: now)
    }

    func s(_ provider: UsageProvider, input: Int, output: Int, cost: Decimal? = nil) -> UsageSample {
        UsageSample(
            id: UUID().uuidString,
            provider: provider,
            modelID: "m1",
            timestamp: now,
            inputTokens: input,
            outputTokens: output,
            costUSD: cost
        )
    }

    @Test func totals() {
        let ss = snap([
            s(UsageProviders.claudeCode, input: 100, output: 50, cost: Decimal(string: "0.10")),
            s(UsageProviders.codex,      input: 200, output: 80, cost: Decimal(string: "0.20")),
        ])
        #expect(ss.totalInputTokens == 300)
        #expect(ss.totalOutputTokens == 130)
        #expect(ss.totalCostUSD == Decimal(string: "0.30"))
    }

    @Test func totalCostIsNilWhenNoSamplesHaveCost() {
        let ss = snap([s(UsageProviders.claudeCode, input: 10, output: 5)])
        #expect(ss.totalCostUSD == nil)
    }

    @Test func filterByProvider() {
        let cc = s(UsageProviders.claudeCode, input: 10, output: 0)
        let cx = s(UsageProviders.codex, input: 20, output: 0)
        let ss = snap([cc, cx])
        let filtered = ss.filtered(by: UsageProviders.claudeCode)
        #expect(filtered.samples.count == 1)
        #expect(filtered.totalInputTokens == 10)
    }

    @Test func filterByDateExcludesOldSamples() {
        let past = Date(timeIntervalSinceReferenceDate: 0)
        let recent = Date(timeIntervalSinceReferenceDate: 2_000_000)
        let sOld = UsageSample(id: "old", provider: UsageProviders.claudeCode, modelID: "m", timestamp: past, inputTokens: 5, outputTokens: 0)
        let sNew = UsageSample(id: "new", provider: UsageProviders.claudeCode, modelID: "m", timestamp: recent, inputTokens: 10, outputTokens: 0)
        let ss = snap([sOld, sNew])
        let filtered = ss.filtered(after: Date(timeIntervalSinceReferenceDate: 1_000_000))
        #expect(filtered.samples.count == 1)
        #expect(filtered.samples[0].id == "new")
    }

    @Test func byProviderGroupsCorrectly() {
        let cc = s(UsageProviders.claudeCode, input: 10, output: 0)
        let cx = s(UsageProviders.codex, input: 20, output: 0)
        let ss = snap([cc, cx])
        let groups = ss.byProvider
        #expect(groups.count == 2)
        #expect(groups[UsageProviders.claudeCode]?.totalInputTokens == 10)
        #expect(groups[UsageProviders.codex]?.totalInputTokens == 20)
    }
}

// MARK: - NullUsageReader

@Suite struct NullUsageReaderTests {
    @Test func alwaysReturnsEmpty() async throws {
        let reader = NullUsageReader(provider: UsageProviders.aider)
        let samples = try await reader.read(since: Date.distantPast)
        #expect(samples.isEmpty)
    }
}

// MARK: - UsageRegistry (async snapshot)

@Suite struct UsageRegistrySnapshotTests {
    @Test func snapshotFromNullReadersIsEmpty() async {
        let registry = UsageRegistry(readers: [
            NullUsageReader(provider: UsageProviders.claudeCode),
            NullUsageReader(provider: UsageProviders.codex),
        ])
        let snapshot = await registry.snapshot(since: Date.distantPast)
        #expect(snapshot.samples.isEmpty)
    }
}
