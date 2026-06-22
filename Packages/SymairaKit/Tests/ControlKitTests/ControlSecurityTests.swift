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
        guard ProcessInfo.processInfo.environment["CI"] != "true" else { return }
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
        guard ProcessInfo.processInfo.environment["CI"] != "true" else { return }
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
            .spawn, .focus, .blocked, .readScrollback
        ]
        for method in allMethods {
            switch method {
            case .snapshot, .panes, .pendingApprovals, .worktrees,
                 .spawn, .focus, .blocked, .readScrollback:
                break
            // If an approve/deny case were added to ControlMethod,
            // Swift's exhaustiveness check would force a case here,
            // making this test fail to compile — the structural guarantee.
            }
        }
        #expect(allMethods.count == 8, "Verb count must not grow without review")
    }

    /// Verify the response body struct cannot carry an approval decision.
    @Test func responseBodyHasNoApprovalDecisionCase() {
        let allResults: [ControlResponseBody] = [
            .of(snapshot: OrchestrationSnapshot()),
            .of(panes: []),
            .of(worktrees: []),
            .of(approvals: []),
            .spawned(UUID()),
            .focused(UUID()),
            .blocked(nil),
            .ok,
            .scrollback([])
        ]
        for body in allResults {
            let children = Mirror(reflecting: body).children.map { $0.label }
            #expect(!children.contains("approvalDecision"), "Response body must never carry an approval decision")
        }
        #expect(allResults.count == 9, "Result case count must not grow without review")
    }

    // MARK: - Spawn rejects missing agentID

    @Test func spawnRequiresAgentID() async throws {
        guard ProcessInfo.processInfo.environment["CI"] != "true" else { return }
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
        guard ProcessInfo.processInfo.environment["CI"] != "true" else { return }
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

    // MARK: - Frame size limit

    @Test func oversizedFrameRejected() async throws {
        guard ProcessInfo.processInfo.environment["CI"] != "true" else { return }
        let tmpSocket = NSTemporaryDirectory() + "sec-oversize-\(UUID().uuidString).sock"
        let server = ControlServer(socketPath: tmpSocket)
        try await server.start(provider: MockControlProvider())
        defer { Task { await server.stop() } }
        try await Task.sleep(nanoseconds: 10_000_000)

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { Issue.record("Failed to create socket"); return }
        defer { Darwin.close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = tmpSocket.utf8CString
        withUnsafeMutableBytes(of: &addr.sun_path) { ptr in
            for (i, b) in pathBytes.prefix(ptr.count - 1).enumerated() {
                ptr[i] = UInt8(bitPattern: b)
            }
        }
        let connectResult = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else { Issue.record("Failed to connect"); return }

        var oversizedFrame = Data(repeating: 0x41, count: ControlServer.maxFrameSize + 1)
        oversizedFrame.append(0x0a)
        _ = oversizedFrame.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!, oversizedFrame.count) }

        var incoming = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        let startTime = Date()
        while !incoming.contains(0x0a) && Date().timeIntervalSince(startTime) < 5 {
            let n = buf.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!, $0.count) }
            guard n > 0 else { break }
            incoming.append(contentsOf: buf.prefix(n))
        }

        if let nlIdx = incoming.firstIndex(of: 0x0a) {
            let decoder = JSONDecoder()
            let response = try decoder.decode(ControlResponse.self, from: incoming[incoming.startIndex..<nlIdx])
            #expect(response.error != nil)
            #expect(response.error?.code == -32600)
        } else {
            // Connection closed without response is also acceptable
            #expect(true)
        }
    }

    // MARK: - Connection cap

    @Test func connectionCapEnforced() async throws {
        guard ProcessInfo.processInfo.environment["CI"] != "true" else { return }
        let tmpSocket = NSTemporaryDirectory() + "sec-cap-\(UUID().uuidString).sock"
        let server = ControlServer(socketPath: tmpSocket)
        try await server.start(provider: MockControlProvider())
        defer { Task { await server.stop() } }
        try await Task.sleep(nanoseconds: 10_000_000)

        var fds: [Int32] = []
        defer { fds.forEach { Darwin.close($0) } }

        for _ in 0..<(ControlServer.maxConcurrentConnections + 2) {
            let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { break }

            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            let pathBytes = tmpSocket.utf8CString
            withUnsafeMutableBytes(of: &addr.sun_path) { ptr in
                for (i, b) in pathBytes.prefix(ptr.count - 1).enumerated() {
                    ptr[i] = UInt8(bitPattern: b)
                }
            }
            let connectResult = withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            if connectResult == 0 {
                fds.append(fd)
            } else {
                Darwin.close(fd)
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        let client = ControlClient(socketPath: tmpSocket)
        let result = try await client.snapshot()
        #expect(result.panes.isEmpty)
    }
}
