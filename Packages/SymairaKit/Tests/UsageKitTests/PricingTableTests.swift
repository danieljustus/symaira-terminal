import Testing
import Foundation
@testable import UsageKit

@Suite struct PricingTableTests {
    func makeTable(_ rates: [String: ModelPricing]) -> PricingTable {
        PricingTable(version: "test", rates: rates)
    }

    func makeSample(
        model: String,
        input: Int = 0,
        output: Int = 0,
        cacheCreate: Int = 0,
        cacheRead: Int = 0
    ) -> UsageSample {
        UsageSample(
            id: UUID().uuidString,
            provider: UsageProviders.claudeCode,
            modelID: model,
            timestamp: Date(),
            inputTokens: input,
            outputTokens: output,
            cacheCreationTokens: cacheCreate,
            cacheReadTokens: cacheRead
        )
    }

    @Test func knownModelReturnsCorrectCost() {
        let table = makeTable([
            "claude-opus-4-5": ModelPricing(
                inputPerMillion: 15.0,
                outputPerMillion: 75.0,
                cacheWritePerMillion: 18.75,
                cacheReadPerMillion: 1.50
            )
        ])
        let sample = makeSample(model: "claude-opus-4-5", input: 1_000_000, output: 1_000_000)
        let cost = table.cost(for: sample)
        #expect(cost == Decimal(90))   // 15 + 75
    }

    @Test func cacheTokensArePricedIndependently() {
        let table = makeTable([
            "claude-opus-4-5": ModelPricing(
                inputPerMillion: 0,
                outputPerMillion: 0,
                cacheWritePerMillion: 18.75,
                cacheReadPerMillion: 1.50
            )
        ])
        let sample = makeSample(
            model: "claude-opus-4-5",
            cacheCreate: 1_000_000,
            cacheRead: 1_000_000
        )
        let cost = table.cost(for: sample)
        #expect(cost == Decimal(string: "20.25"))  // 18.75 + 1.50
    }

    @Test func unknownModelReturnsNil() {
        let table = makeTable([:])
        let sample = makeSample(model: "gpt-99-turbo")
        #expect(table.cost(for: sample) == nil)
    }

    @Test func zeroTokensProduceZeroCost() {
        let table = makeTable([
            "claude-haiku-4-5-20251001": ModelPricing(
                inputPerMillion: 0.80,
                outputPerMillion: 4.00
            )
        ])
        let sample = makeSample(model: "claude-haiku-4-5-20251001")
        #expect(table.cost(for: sample) == .zero)
    }

    @Test func parsingFromJSONData() throws {
        let json = Data("""
        {
          "_version": "2026-06-14",
          "models": {
            "test-model": {
              "inputPerMillion": 2.0,
              "outputPerMillion": 8.0,
              "cacheWritePerMillion": 0.5,
              "cacheReadPerMillion": 0.1
            }
          }
        }
        """.utf8)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pricing-test-\(UUID().uuidString).json")
        try json.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let table = try PricingTable(contentsOf: url)
        #expect(table.version == "2026-06-14")

        let sample = makeSample(model: "test-model", input: 1_000_000, output: 1_000_000)
        let cost = table.cost(for: sample)
        #expect(cost == Decimal(10))  // 2 + 8
    }

    @Test func subscriptReturnsNilForMissingModel() {
        let table = makeTable([:])
        #expect(table["nonexistent"] == nil)
    }
}

@Suite struct ModelPricingTests {
    @Test func partialTokenCost() {
        let pricing = ModelPricing(inputPerMillion: 3.0, outputPerMillion: 15.0)
        // 500k input + 100k output
        let cost = pricing.cost(inputTokens: 500_000, outputTokens: 100_000)
        // 0.5 * 3 + 0.1 * 15 = 1.5 + 1.5 = 3.0
        #expect(cost == Decimal(3))
    }
}
