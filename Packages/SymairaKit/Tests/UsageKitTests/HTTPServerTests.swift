import Testing
import Foundation
@testable import UsageKit

@Suite struct UsageHTTPServerTests {
    @Test func defaultPortIs6737() {
        #expect(UsageHTTPServer.defaultPort == 6737)
    }

    @Test func serverStartsAndStops() async throws {
        let server = UsageHTTPServer(
            port: 16737,  // high port to avoid permission issues in CI
            snapshotProvider: { UsageSnapshot(samples: [], generatedAt: Date()) },
            quotaProvider: { QuotaRegistry.QuotaResult(quotas: [], errors: [:]) }
        )
        // Start — should not throw
        try await server.start()
        let running = await server.isRunning
        #expect(running)

        // Stop
        await server.stop()
        let stopped = await server.isRunning
        #expect(!stopped)
    }

    @Test func startIsIdempotent() async throws {
        let server = UsageHTTPServer(
            port: 16738,
            snapshotProvider: { UsageSnapshot(samples: [], generatedAt: Date()) },
            quotaProvider: { QuotaRegistry.QuotaResult(quotas: [], errors: [:]) }
        )
        try await server.start()
        try await server.start()  // second call should be no-op
        let running = await server.isRunning
        #expect(running)
        await server.stop()
    }

    @Test func allowsLoopbackHosts() {
        #expect(UsageHTTPServer.isAllowedHost("127.0.0.1"))
        #expect(UsageHTTPServer.isAllowedHost("127.0.0.1:6737"))
        #expect(UsageHTTPServer.isAllowedHost("localhost"))
        #expect(UsageHTTPServer.isAllowedHost("localhost:6737"))
        #expect(UsageHTTPServer.isAllowedHost("LOCALHOST"))
        #expect(UsageHTTPServer.isAllowedHost("[::1]:6737"))
        #expect(UsageHTTPServer.isAllowedHost("::1"))
    }

    @Test func rejectsNonLoopbackOrMissingHosts() {
        #expect(!UsageHTTPServer.isAllowedHost(nil))
        #expect(!UsageHTTPServer.isAllowedHost(""))
        #expect(!UsageHTTPServer.isAllowedHost("evil.com"))
        #expect(!UsageHTTPServer.isAllowedHost("evil.com:6737"))
        #expect(!UsageHTTPServer.isAllowedHost("0.0.0.0"))
        #expect(!UsageHTTPServer.isAllowedHost("127.0.0.1.evil.com"))
    }

    @Test func parsesHostHeaderCaseInsensitively() {
        let lines = ["GET /usage HTTP/1.1", "Host: 127.0.0.1:6737", "Accept: */*"]
        #expect(UsageHTTPServer.headerValue(named: "host", in: lines) == "127.0.0.1:6737")
        let lower = ["GET / HTTP/1.1", "host:   localhost  "]
        #expect(UsageHTTPServer.headerValue(named: "Host", in: lower) == "localhost")
        #expect(UsageHTTPServer.headerValue(named: "Host", in: ["GET / HTTP/1.1"]) == nil)
    }
}
