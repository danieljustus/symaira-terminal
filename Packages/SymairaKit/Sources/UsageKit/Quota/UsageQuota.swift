import Foundation

/// A snapshot of subscription plan consumption for one provider.
///
/// `used` and `limit` are abstract "units" whose meaning depends on the
/// provider: Claude returns token counts for session and weekly limits;
/// Cursor returns credit counts. UI layers format the unit appropriately.
public struct UsageQuota: Equatable, Sendable {
    public enum Unit: String, Equatable, Sendable {
        case tokens
        case credits
        case requests
        case unknown
    }

    public let provider: UsageProvider
    public let label: String    // e.g. "Session", "Weekly", "Credits"
    public let used: Int
    public let limit: Int?      // nil = unlimited or unknown
    public let resetsAt: Date?  // nil = unknown
    public let unit: Unit
    public let fetchedAt: Date

    public var fractionUsed: Double? {
        guard let limit, limit > 0 else { return nil }
        return Double(used) / Double(limit)
    }

    public var percentUsed: Double? {
        fractionUsed.map { $0 * 100 }
    }

    public init(
        provider: UsageProvider,
        label: String,
        used: Int,
        limit: Int? = nil,
        resetsAt: Date? = nil,
        unit: Unit = .tokens,
        fetchedAt: Date
    ) {
        self.provider = provider
        self.label = label
        self.used = used
        self.limit = limit
        self.resetsAt = resetsAt
        self.unit = unit
        self.fetchedAt = fetchedAt
    }
}

/// Error types for quota fetchers — kept separate from `UsageReader` errors
/// so the UI can surface "unauthorized" vs. "unavailable" distinctly.
public enum QuotaFetchError: Error, Sendable, Equatable {
    case notEnabled
    case unauthorized
    case networkUnavailable
    case unsupportedProvider
    case unexpectedResponse(String)
}

/// The protocol every subscription quota fetcher implements.
/// All fetchers are **opt-in**: callers must check `isEnabled` before fetching.
public protocol QuotaFetcher: Sendable {
    var provider: UsageProvider { get }

    /// Whether the user has explicitly enabled quota fetching for this provider.
    var isEnabled: Bool { get }

    /// Fetch the current quota snapshot. Throws `QuotaFetchError.notEnabled`
    /// when `isEnabled == false` so callers can guard uniformly.
    func fetchQuota() async throws -> [UsageQuota]
}
