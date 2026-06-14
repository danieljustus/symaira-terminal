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
        try server.start()
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
        try server.start()
        try server.start()  // second call should be no-op
        let running = await server.isRunning
        #expect(running)
        await server.stop()
    }
}
