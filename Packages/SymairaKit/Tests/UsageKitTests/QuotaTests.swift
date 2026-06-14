import Testing
import Foundation
@testable import UsageKit

// MARK: - UsageQuota

@Suite struct UsageQuotaTests {
    @Test func fractionUsedWithKnownLimit() {
        let q = UsageQuota(
            provider: UsageProviders.claudeCode,
            label: "Session",
            used: 500,
            limit: 1000,
            unit: .tokens,
            fetchedAt: Date()
        )
        #expect(q.fractionUsed == 0.5)
        #expect(q.percentUsed == 50.0)
    }

    @Test func fractionUsedWithNoLimit() {
        let q = UsageQuota(
            provider: UsageProviders.claudeCode,
            label: "Session",
            used: 500,
            limit: nil,
            unit: .tokens,
            fetchedAt: Date()
        )
        #expect(q.fractionUsed == nil)
        #expect(q.percentUsed == nil)
    }

    @Test func fractionUsedWithZeroLimit() {
        let q = UsageQuota(
            provider: UsageProviders.claudeCode,
            label: "Session",
            used: 10,
            limit: 0,
            unit: .tokens,
            fetchedAt: Date()
        )
        #expect(q.fractionUsed == nil)
    }
}

// MARK: - AnthropicQuotaFetcher

@Suite struct AnthropicQuotaFetcherTests {
    @Test func throwsNotEnabledWhenDisabled() async {
        let fetcher = AnthropicQuotaFetcher(isEnabled: false, apiKey: "sk-test")
        do {
            _ = try await fetcher.fetchQuota()
            #expect(Bool(false), "Expected throw")
        } catch QuotaFetchError.notEnabled {
            // expected
        } catch {
            #expect(Bool(false), "Wrong error: \(error)")
        }
    }

    @Test func throwsUnauthorizedWithNoKey() async {
        let fetcher = AnthropicQuotaFetcher(isEnabled: true, apiKey: nil)
        do {
            _ = try await fetcher.fetchQuota()
            #expect(Bool(false), "Expected throw")
        } catch QuotaFetchError.unauthorized {
            // expected
        } catch {
            #expect(Bool(false), "Wrong error: \(error)")
        }
    }

    @Test func throwsUnauthorizedWithEmptyKey() async {
        let fetcher = AnthropicQuotaFetcher(isEnabled: true, apiKey: "")
        do {
            _ = try await fetcher.fetchQuota()
            #expect(Bool(false), "Expected throw")
        } catch QuotaFetchError.unauthorized {
            // expected
        } catch {
            #expect(Bool(false), "Wrong error: \(error)")
        }
    }
}

// MARK: - QuotaRegistry

/// A stub fetcher for registry tests — always returns a fixed quota.
private struct StubQuotaFetcher: QuotaFetcher {
    let provider: UsageProvider
    let isEnabled: Bool
    let result: Result<[UsageQuota], QuotaFetchError>

    func fetchQuota() async throws -> [UsageQuota] {
        try result.get()
    }
}

@Suite struct QuotaRegistryTests {
    @Test func aggregatesResultsFromMultipleFetchers() async {
        let q1 = UsageQuota(
            provider: UsageProviders.claudeCode, label: "Session",
            used: 100, unit: .tokens, fetchedAt: Date()
        )
        let q2 = UsageQuota(
            provider: UsageProviders.codex, label: "Credits",
            used: 5, unit: .credits, fetchedAt: Date()
        )
        let registry = QuotaRegistry(fetchers: [
            StubQuotaFetcher(provider: UsageProviders.claudeCode, isEnabled: true, result: .success([q1])),
            StubQuotaFetcher(provider: UsageProviders.codex, isEnabled: true, result: .success([q2])),
        ])
        let result = await registry.fetchAll()
        #expect(result.quotas.count == 2)
        #expect(result.errors.isEmpty)
    }

    @Test func disabledFetcherDoesNotProduceError() async {
        let registry = QuotaRegistry(fetchers: [
            StubQuotaFetcher(
                provider: UsageProviders.claudeCode,
                isEnabled: false,
                result: .failure(.notEnabled)
            ),
        ])
        let result = await registry.fetchAll()
        #expect(result.quotas.isEmpty)
        #expect(result.errors.isEmpty)  // notEnabled is NOT an error
    }

    @Test func networkErrorIsRecordedInErrors() async {
        let registry = QuotaRegistry(fetchers: [
            StubQuotaFetcher(
                provider: UsageProviders.claudeCode,
                isEnabled: true,
                result: .failure(.networkUnavailable)
            ),
        ])
        let result = await registry.fetchAll()
        #expect(result.quotas.isEmpty)
        #expect(result.errors[UsageProviders.claudeCode] == .networkUnavailable)
    }

    @Test func oneFailingFetcherDoesNotBlockSuccessfulOne() async {
        let q = UsageQuota(
            provider: UsageProviders.codex, label: "Credits",
            used: 3, unit: .credits, fetchedAt: Date()
        )
        let registry = QuotaRegistry(fetchers: [
            StubQuotaFetcher(provider: UsageProviders.claudeCode, isEnabled: true,
                             result: .failure(.networkUnavailable)),
            StubQuotaFetcher(provider: UsageProviders.codex, isEnabled: true,
                             result: .success([q])),
        ])
        let result = await registry.fetchAll()
        #expect(result.quotas.count == 1)
        #expect(result.errors.count == 1)
    }
}
