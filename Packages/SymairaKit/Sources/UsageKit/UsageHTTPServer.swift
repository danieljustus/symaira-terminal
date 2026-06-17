import Foundation
import Network

/// An opt-in, loopback-only HTTP server that exposes the current usage snapshot
/// as JSON so other local tools can consume it without re-implementing the readers.
///
/// Off by default. Only starts when the user explicitly enables it in Settings.
/// Binds exclusively to 127.0.0.1 — external addresses are rejected at the API level.
/// All endpoints are read-only; no write operations are exposed.
/// Secrets are never included in any response (the snapshot contains no credentials).
public actor UsageHTTPServer {
    public static let defaultPort: UInt16 = 6737  // one above openusage's 6736

    private let port: UInt16
    private var listener: NWListener?
    private var snapshotProvider: @Sendable () async -> UsageSnapshot
    private var quotaProvider: @Sendable () async -> QuotaRegistry.QuotaResult

    public private(set) var isRunning: Bool = false

    public init(
        port: UInt16 = defaultPort,
        snapshotProvider: @escaping @Sendable () async -> UsageSnapshot,
        quotaProvider: @escaping @Sendable () async -> QuotaRegistry.QuotaResult
    ) {
        self.port = port
        self.snapshotProvider = snapshotProvider
        self.quotaProvider = quotaProvider
    }

    // MARK: - Lifecycle

    /// Start the server. Throws if binding to the port fails.
    /// Only call this after the user has explicitly enabled the feature.
    public func start() throws {
        guard !isRunning else { return }

        let params = NWParameters.tcp
        // Loopback-only: restrict to 127.0.0.1.
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: port)!
        )
        params.allowLocalEndpointReuse = true

        let l = try NWListener(using: params)
        l.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task { await self.handle(connection: connection) }
        }
        l.start(queue: .global(qos: .utility))
        listener = l
        isRunning = true
    }

    /// Stop the server and release the port.
    public func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    // MARK: - Request handling

    private func handle(connection: NWConnection) async {
        connection.start(queue: .global(qos: .utility))

        var requestData = Data()
        var headerTerminatorFound = false

        while !headerTerminatorFound {
            let chunk = await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                    cont.resume(returning: data)
                }
            }

            guard let chunk = chunk, !chunk.isEmpty else {
                connection.cancel()
                return
            }

            requestData.append(chunk)

            if let requestString = String(data: requestData, encoding: .utf8),
               requestString.contains("\r\n\r\n") {
                headerTerminatorFound = true
            }
        }

        let requestText = String(data: requestData, encoding: .utf8) ?? ""
        let lines = requestText.components(separatedBy: "\r\n")
        let requestLine = lines.first ?? ""
        let path = requestLine.components(separatedBy: " ").dropFirst().first ?? "/"
        let host = Self.headerValue(named: "host", in: lines)

        // Reject anything not addressed to the loopback host. The socket already
        // binds to 127.0.0.1, but a browser the user visits could reach this port
        // via DNS-rebinding; a Host-header allowlist closes that probe surface.
        let (statusCode, body): (Int, Data)
        if !Self.isAllowedHost(host) {
            statusCode = 403
            body = Data("{\"error\":\"forbidden host\"}".utf8)
        } else {
            (statusCode, body) = await buildResponse(path: path)
        }
        let response = httpResponse(statusCode: statusCode, body: body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// Case-insensitive lookup of a single header value from the raw request lines.
    static func headerValue(named name: String, in lines: [String]) -> String? {
        let prefix = name.lowercased() + ":"
        for line in lines.dropFirst() where line.lowercased().hasPrefix(prefix) {
            return line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// Accepts only loopback hosts (with optional port). A missing Host header is
    /// rejected — every legitimate local client sends one.
    static func isAllowedHost(_ host: String?) -> Bool {
        guard let host, !host.isEmpty else { return false }
        // Strip the port. IPv6 literals are bracketed: [::1]:6737.
        let hostname: String
        if host.hasPrefix("[") {
            // Bracketed IPv6 literal, optionally with :port — take inside the brackets.
            hostname = String(host.dropFirst().prefix { $0 != "]" })
        } else if host.filter({ $0 == ":" }).count == 1, let colon = host.firstIndex(of: ":") {
            // Exactly one colon → host:port (IPv4 or name). Multiple colons with no
            // brackets is a bare IPv6 literal, which carries no port to strip.
            hostname = String(host[..<colon])
        } else {
            hostname = host
        }
        let allowed: Set<String> = ["127.0.0.1", "localhost", "::1"]
        return allowed.contains(hostname.lowercased())
    }

    private func buildResponse(path: String) async -> (Int, Data) {
        switch path {
        case "/usage", "/usage/snapshot":
            let snapshot = await snapshotProvider()
            let payload = snapshotJSON(snapshot)
            return (200, payload)

        case "/usage/quota":
            let quota = await quotaProvider()
            let payload = quotaJSON(quota)
            return (200, payload)

        case "/health":
            let payload = Data("{\"status\":\"ok\",\"port\":\(port)}".utf8)
            return (200, payload)

        default:
            let payload = Data("{\"error\":\"not found\"}".utf8)
            return (404, payload)
        }
    }

    // MARK: - JSON serialization (manual — no secrets, no credentials)

    private func snapshotJSON(_ snapshot: UsageSnapshot) -> Data {
        var obj: [String: Any] = [
            "generatedAt": ISO8601DateFormatter().string(from: snapshot.generatedAt),
            "totalInputTokens": snapshot.totalInputTokens,
            "totalOutputTokens": snapshot.totalOutputTokens,
            "totalCacheCreationTokens": snapshot.totalCacheCreationTokens,
            "totalCacheReadTokens": snapshot.totalCacheReadTokens,
            "totalTokens": snapshot.totalTokens,
            "sampleCount": snapshot.samples.count
        ]
        if let cost = snapshot.totalCostUSD {
            obj["totalCostUSD"] = (cost as NSDecimalNumber).doubleValue
        }
        // Expose per-provider rollup; never include sourcePath or credential fields.
        let byProvider = snapshot.byProvider.map { (provider, s) -> [String: Any] in
            var p: [String: Any] = [
                "provider": provider.id,
                "displayName": provider.displayName,
                "inputTokens": s.totalInputTokens,
                "outputTokens": s.totalOutputTokens,
                "totalTokens": s.totalTokens
            ]
            if let c = s.totalCostUSD { p["costUSD"] = (c as NSDecimalNumber).doubleValue }
            return p
        }
        obj["byProvider"] = byProvider
        return (try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted)) ?? Data()
    }

    private func quotaJSON(_ result: QuotaRegistry.QuotaResult) -> Data {
        let quotas = result.quotas.map { q -> [String: Any] in
            var entry: [String: Any] = [
                "provider": q.provider.id,
                "label": q.label,
                "used": q.used,
                "unit": q.unit.rawValue,
                "fetchedAt": ISO8601DateFormatter().string(from: q.fetchedAt)
            ]
            if let limit = q.limit { entry["limit"] = limit }
            if let resets = q.resetsAt { entry["resetsAt"] = ISO8601DateFormatter().string(from: resets) }
            return entry
        }
        let obj: [String: Any] = ["quotas": quotas]
        return (try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted)) ?? Data()
    }

    // MARK: - HTTP framing

    private func httpResponse(statusCode: Int, body: Data) -> Data {
        let header = "HTTP/1.1 \(statusCode) \(statusText(statusCode))\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: \(body.count)\r\n"
            + "Connection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        return response
    }

    private func statusText(_ code: Int) -> String {
        switch code {
        case 200: "OK"
        case 403: "Forbidden"
        case 404: "Not Found"
        default:  "Unknown"
        }
    }
}
