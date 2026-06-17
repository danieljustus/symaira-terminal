import ControlKit
import Foundation
import Testing

/// Verifies the security boundary of the control surface:
/// - Socket is created with 0600 (owner-only) permissions.
/// - ControlMethod has no approve/deny verbs (structural capability check).
/// - Stopped server cleans up the socket path.
@Suite("Control surface security boundary")
struct ControlSecurityTests {

    // MARK: - Socket permissions

    @Test func socketCreatedWith600Permissions() async throws {
        let tmpSocket = NSTemporaryDirectory() + "sec-test-\(UUID().uuidString).sock"
        let provider = MockControlProvider()
        let server = ControlServer(socketPath: tmpSocket)
        try await server.start(provider: provider)
        defer { Task { await server.stop() } }

        // Give the OS time to flush the bind before we stat
        try await Task.sleep(nanoseconds: 5_000_000)

        let attrs = try FileManager.default.attributesOfItem(atPath: tmpSocket)
        let posixPerms = attrs[.posixPermissions] as? Int
        // 0600 = 384 decimal; only owner read+write, no group or other bits
        #expect(posixPerms == 0o600,
            "Socket must be 0600 so only the owning user can connect; got \(String(posixPerms.map { String($0, radix: 8) } ?? "nil"))")
    }

    @Test func socketRemovedAfterStop() async throws {
        let tmpSocket = NSTemporaryDirectory() + "sec-stop-\(UUID().uuidString).sock"
        let server = ControlServer(socketPath: tmpSocket)
        try await server.start(provider: MockControlProvider())
        try await Task.sleep(nanoseconds: 5_000_000)

        #expect(FileManager.default.fileExists(atPath: tmpSocket),
            "Socket file should exist while server is running")

        await server.stop()
        try await Task.sleep(nanoseconds: 5_000_000)

        #expect(!FileManager.default.fileExists(atPath: tmpSocket),
            "Socket file should be removed on stop to prevent stale-socket reconnection")
    }

    // MARK: - Capability boundary (approve/deny structurally absent)

    /// Exhaustive switch over ControlMethod ensures approve/deny cases
    /// cannot exist: adding them would break this switch at compile time.
    @Test func controlMethodHasNoApproveOrDenyVerb() {
        let allMethods: [ControlMethod] = [
            .snapshot, .panes, .pendingApprovals, .worktrees,
            .spawn, .focus, .blocked
        ]
        for method in allMethods {
            switch method {
            case .snapshot, .panes, .pendingApprovals, .worktrees,
                 .spawn, .focus, .blocked:
                break
            // If an approve/deny case were added to ControlMethod,
            // Swift's exhaustiveness check would force a case here,
            // making this test fail to compile — the structural guarantee.
            }
        }
        #expect(allMethods.count == 7, "Verb count must not grow without review")
    }

    /// Verify no control response body field can carry an approval decision.
    @Test func responseBodyHasNoApprovalDecisionField() {
        // ControlResponseBody must not have an approveDecision or denyDecision field.
        // We verify the field list via Mirror reflection.
        let body = ControlResponseBody.ok
        let mirror = Mirror(reflecting: body)
        let fieldNames = mirror.children.compactMap(\.label)
        let forbidden = fieldNames.filter {
            $0.lowercased().contains("approve") || $0.lowercased().contains("deny")
        }
        #expect(forbidden.isEmpty,
            "ControlResponseBody must not contain approve/deny fields: \(forbidden)")
    }

    // MARK: - Spawn rejects missing agentID

    @Test func spawnRequiresAgentID() async throws {
        let tmpSocket = NSTemporaryDirectory() + "sec-spawn-\(UUID().uuidString).sock"
        let server = ControlServer(socketPath: tmpSocket)
        try await server.start(provider: MockControlProvider())
        defer { Task { await server.stop() } }
        try await Task.sleep(nanoseconds: 10_000_000)

        let client = ControlClient(socketPath: tmpSocket)
        // Send a spawn request without agentID — should return an RPC error
        let request = ControlRequest(method: .spawn, params: ControlParams(), id: 42)
        do {
            _ = try await client.send(request)
            Issue.record("Expected rpcError for missing agentID")
        } catch ControlClientError.rpcError(let err) {
            #expect(err.code == -32602) // invalidParams
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - Focus rejects missing paneID

    @Test func focusRequiresPaneID() async throws {
        let tmpSocket = NSTemporaryDirectory() + "sec-focus-\(UUID().uuidString).sock"
        let server = ControlServer(socketPath: tmpSocket)
        try await server.start(provider: MockControlProvider())
        defer { Task { await server.stop() } }
        try await Task.sleep(nanoseconds: 10_000_000)

        let client = ControlClient(socketPath: tmpSocket)
        let request = ControlRequest(method: .focus, params: ControlParams(), id: 43)
        do {
            _ = try await client.send(request)
            Issue.record("Expected rpcError for missing paneID")
        } catch ControlClientError.rpcError(let err) {
            #expect(err.code == -32602)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
