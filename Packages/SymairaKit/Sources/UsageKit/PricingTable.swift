import Foundation

/// Per-model pricing rates in USD per million tokens.
public struct ModelPricing: Equatable, Sendable {
    public let inputPerMillion: Decimal
    public let outputPerMillion: Decimal
    public let cacheWritePerMillion: Decimal
    public let cacheReadPerMillion: Decimal

    public init(
        inputPerMillion: Decimal,
        outputPerMillion: Decimal,
        cacheWritePerMillion: Decimal = .zero,
        cacheReadPerMillion: Decimal = .zero
    ) {
        self.inputPerMillion = inputPerMillion
        self.outputPerMillion = outputPerMillion
        self.cacheWritePerMillion = cacheWritePerMillion
        self.cacheReadPerMillion = cacheReadPerMillion
    }

    /// Compute cost in USD for a sample with the given token counts.
    public func cost(
        inputTokens: Int,
        outputTokens: Int,
        cacheCreationTokens: Int = 0,
        cacheReadTokens: Int = 0
    ) -> Decimal {
        let m = Decimal(1_000_000)
        return (Decimal(inputTokens) / m * inputPerMillion)
             + (Decimal(outputTokens) / m * outputPerMillion)
             + (Decimal(cacheCreationTokens) / m * cacheWritePerMillion)
             + (Decimal(cacheReadTokens) / m * cacheReadPerMillion)
    }
}

/// Versioned, bundled pricing table keyed by model id.
/// `cost(for:)` returns nil for unknown models so callers can fall back to
/// a tokens-only display without crashing.
public struct PricingTable: Sendable {
    public let version: String
    private let rates: [String: ModelPricing]

    public init(version: String, rates: [String: ModelPricing]) {
        self.version = version
        self.rates = rates
    }

    public subscript(modelID: String) -> ModelPricing? { rates[modelID] }

    /// Compute USD cost for a sample, or return nil if the model is unknown.
    public func cost(for sample: UsageSample) -> Decimal? {
        guard let pricing = rates[sample.modelID] else { return nil }
        return pricing.cost(
            inputTokens: sample.inputTokens,
            outputTokens: sample.outputTokens,
            cacheCreationTokens: sample.cacheCreationTokens,
            cacheReadTokens: sample.cacheReadTokens
        )
    }

    // MARK: - Bundled default

    /// The default table loaded from the bundled `pricing.json` resource.
    public static let bundled: PricingTable = loadBundled()

    private static func loadBundled() -> PricingTable {
        // Walk from this file's directory up to find the Resources folder.
        // SPM includes resources via Bundle.module in Swift 5.3+, but we target
        // a directory alongside the Sources tree to keep it simple.
        let candidates: [URL] = {
            var urls: [URL] = []
            // Relative to the built binary (SPM targets embed resources under
            // `<target>.resources/` in the build directory).
            if let url = Bundle.module.url(forResource: "pricing", withExtension: "json") {
                urls.append(url)
            }
            return urls
        }()

        for url in candidates {
            if let table = try? PricingTable(contentsOf: url) { return table }
        }
        // Fallback: empty table with no known models.
        return PricingTable(version: "fallback", rates: [:])
    }

    public init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            ?? { throw PricingError.invalidFormat }()
        let version = json["_version"] as? String ?? "unknown"
        let modelsDict = json["models"] as? [String: Any] ?? [:]
        var rates: [String: ModelPricing] = [:]
        for (modelID, rawValue) in modelsDict {
            guard let entry = rawValue as? [String: Any] else { continue }
            let inputPM  = Decimal(string: "\(entry["inputPerMillion"] ?? 0)")  ?? .zero
            let outputPM = Decimal(string: "\(entry["outputPerMillion"] ?? 0)") ?? .zero
            let cWritePM = Decimal(string: "\(entry["cacheWritePerMillion"] ?? 0)") ?? .zero
            let cReadPM  = Decimal(string: "\(entry["cacheReadPerMillion"] ?? 0)")  ?? .zero
            rates[modelID] = ModelPricing(
                inputPerMillion: inputPM,
                outputPerMillion: outputPM,
                cacheWritePerMillion: cWritePM,
                cacheReadPerMillion: cReadPM
            )
        }
        self.version = version
        self.rates = rates
    }
}

public enum PricingError: Error {
    case invalidFormat
}
