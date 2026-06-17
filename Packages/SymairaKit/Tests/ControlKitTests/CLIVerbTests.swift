import ControlKit
import Foundation
import Testing

/// Tests for write-verb request construction and response handling via the
/// control socket. Uses a mock provider — no GUI or PaneManager involved.
@Suite("symterminal CLI write verbs")
struct CLIVerbTests {

    // MARK: - spawn verb

    @Test func spawnCreatesNewPane() async throws {
        let tmpSocket = NSTemporaryDirectory() + "cli-spawn-\(UUID().uuidString).sock"
        let provider = MockControlProvider()
        let server = ControlServer(socketPath: tmpSocket)
        try await server.start(provider: provider)
        defer { Task { await server.stop() } }
        try await Task.sleep(nanoseconds: 10_000_000)

        let client = ControlClient(socketPath: tmpSocket)
        let paneID = try await client.spawn(
            agentID: "claude-code",
            worktreeBranch: "symaira/task-99",
            workingDirectory: "/tmp/work"
        )

        let spawned = await provider.spawnedPanes
        #expect(spawned.count == 1)
        #expect(spawned[0].agentID == "claude-code")
        #expect(spawned[0].branch == "symaira/task-99")
        #expect(spawned[0].cwd == "/tmp/work")
        #expect(paneID != UUID())
    }

    @Test func spawnWithoutWorktree() async throws {
        let tmpSocket = NSTemporaryDirectory() + "cli-spawn2-\(UUID().uuidString).sock"
        let provider = MockControlProvider()
        let server = ControlServer(socketPath: tmpSocket)
        try await server.start(provider: provider)
        defer { Task { await server.stop() } }
        try await Task.sleep(nanoseconds: 10_000_000)

        let client = ControlClient(socketPath: tmpSocket)
        _ = try await client.spawn(agentID: "opencode")

        let spawned = await provider.spawnedPanes
        #expect(spawned[0].branch == nil)
        #expect(spawned[0].cwd == nil)
    }

    // MARK: - focus verb

    @Test func focusKnownPane() async throws {
        let tmpSocket = NSTemporaryDirectory() + "cli-focus-\(UUID().uuidString).sock"
        let target = UUID()
        let provider = MockControlProvider(snapshot: OrchestrationSnapshot(
            panes: [PaneSnapshot(id: target, title: "main")]
        ))
        let server = ControlServer(socketPath: tmpSocket)
        try await server.start(provider: provider)
        defer { Task { await server.stop() } }
        try await Task.sleep(nanoseconds: 10_000_000)

        let client = ControlClient(socketPath: tmpSocket)
        try await client.focus(paneID: target)

        let focused = await provider.focusedIDs
        #expect(focused.first == target)
    }

    @Test func focusMissingPaneReturnsError() async throws {
        let tmpSocket = NSTemporaryDirectory() + "cli-focus2-\(UUID().uuidString).sock"
        let provider = MockControlProvider()
        let server = ControlServer(socketPath: tmpSocket)
        try await server.start(provider: provider)
        defer { Task { await server.stop() } }
        try await Task.sleep(nanoseconds: 10_000_000)

        let client = ControlClient(socketPath: tmpSocket)
        do {
            try await client.focus(paneID: UUID())
            Issue.record("Expected error for unknown pane")
        } catch ControlClientError.rpcError {
            // expected
        }
    }

    // MARK: - blocked verb

    @Test func blockedReturnsLongestWaitingPane() async throws {
        let tmpSocket = NSTemporaryDirectory() + "cli-blocked-\(UUID().uuidString).sock"
        let blockedID = UUID()
        let provider = MockControlProvider()
        await provider.setBlockedID(blockedID)
        let server = ControlServer(socketPath: tmpSocket)
        try await server.start(provider: provider)
        defer { Task { await server.stop() } }
        try await Task.sleep(nanoseconds: 10_000_000)

        let client = ControlClient(socketPath: tmpSocket)
        let result = try await client.blocked()
        #expect(result == blockedID)
    }

    @Test func blockedReturnsNilWhenNoneBlocked() async throws {
        let tmpSocket = NSTemporaryDirectory() + "cli-blocked2-\(UUID().uuidString).sock"
        let provider = MockControlProvider()
        let server = ControlServer(socketPath: tmpSocket)
        try await server.start(provider: provider)
        defer { Task { await server.stop() } }
        try await Task.sleep(nanoseconds: 10_000_000)

        let client = ControlClient(socketPath: tmpSocket)
        let result = try await client.blocked()
        #expect(result == nil)
    }

    // MARK: - No approve/deny verbs in the protocol

    @Test func noApproveVerbExistsInControlMethod() {
        // ControlMethod is exhaustively covered — if approve/deny were added,
        // this switch would require new cases and fail to compile.
        let allCases: [ControlMethod] = [
            .snapshot, .panes, .pendingApprovals, .worktrees,
            .spawn, .focus, .blocked
        ]
        for method in allCases {
            switch method {
            case .snapshot, .panes, .pendingApprovals, .worktrees, .spawn, .focus, .blocked:
                break
            }
        }
        #expect(allCases.count == 7)
    }
}

// Extension to MockControlProvider to support setting blockedID from tests
extension MockControlProvider {
    func setBlockedID(_ id: UUID?) {
        blockedID = id
    }
}
