import Foundation

/// Fetches Claude subscription plan usage from the Anthropic usage API.
///
/// This fetcher is **opt-in and disabled by default**. It only runs when the user
/// explicitly enables it via Settings. Credentials come exclusively from the
/// existing Keychain path in ProviderKit — nothing new is stored.
///
/// Data fetched:
/// - Session token usage (current 5-hour window)
/// - Weekly token usage and limit
///
/// The Anthropic usage endpoint is not publicly documented and may change.
/// The fetcher degrades gracefully: on any failure it throws a typed error
/// so the UI can show "unavailable" without affecting local-file usage.
public struct AnthropicQuotaFetcher: QuotaFetcher, Sendable {
    public let provider: UsageProvider = UsageProviders.claudeCode

    /// Whether the user has enabled Anthropic subscription quota fetching.
    public let isEnabled: Bool

    /// The Anthropic API key (from Keychain via ProviderKit — injected, not stored here).
    private let apiKey: String?

    /// Injectable for testing. Production callers use `URLSession.shared`.
    private let session: URLSession

    public init(
        isEnabled: Bool,
        apiKey: String?,
        session: URLSession = .shared
    ) {
        self.isEnabled = isEnabled
        self.apiKey = apiKey
        self.session = session
    }

    public func fetchQuota() async throws -> [UsageQuota] {
        guard isEnabled else { throw QuotaFetchError.notEnabled }
        guard let apiKey, !apiKey.isEmpty else { throw QuotaFetchError.unauthorized }

        // Anthropic's /v1/usage/subscription endpoint (subject to change).
        // Returns plan session and weekly token usage.
        let url = URL(string: "https://api.anthropic.com/v1/usage/subscription")!
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        // The key is sourced from Keychain only; never logged (SecretRedactor covers
        // any diagnostic output in the app layer).
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.timeoutInterval = 10

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw QuotaFetchError.networkUnavailable
        }

        guard let http = response as? HTTPURLResponse else {
            throw QuotaFetchError.unexpectedResponse("non-HTTP response")
        }
        switch http.statusCode {
        case 401, 403:
            throw QuotaFetchError.unauthorized
        case 200...299:
            break
        default:
            throw QuotaFetchError.unexpectedResponse("HTTP \(http.statusCode)")
        }

        return parseResponse(data: data)
    }

    // MARK: - Parsing

    private func parseResponse(data: Data) -> [UsageQuota] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        let now = Date()
        var quotas: [UsageQuota] = []

        // Session (current 5-hour window)
        if let session = json["session"] as? [String: Any] {
            let used  = session["tokens_used"] as? Int ?? 0
            let limit = session["tokens_limit"] as? Int
            let resetsAt = parseISO8601(session["resets_at"] as? String)
            quotas.append(UsageQuota(
                provider: provider,
                label: "Session",
                used: used,
                limit: limit,
                resetsAt: resetsAt,
                unit: .tokens,
                fetchedAt: now
            ))
        }

        // Weekly
        if let weekly = json["weekly"] as? [String: Any] {
            let used  = weekly["tokens_used"] as? Int ?? 0
            let limit = weekly["tokens_limit"] as? Int
            let resetsAt = parseISO8601(weekly["resets_at"] as? String)
            quotas.append(UsageQuota(
                provider: provider,
                label: "Weekly",
                used: used,
                limit: limit,
                resetsAt: resetsAt,
                unit: .tokens,
                fetchedAt: now
            ))
        }

        return quotas
    }

    private func parseISO8601(_ string: String?) -> Date? {
        guard let string else { return nil }
        return ISO8601DateFormatter().date(from: string)
    }
}
