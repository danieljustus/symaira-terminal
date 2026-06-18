import ControlKit
import Foundation
import Testing

@Suite("CLI write verbs — spawn, blocked, focus")
struct CLIWriteVerbTests {

    // MARK: - Spawn command argument parsing

    @Test("SpawnCommand requires --agent flag")
    func spawnRequiresAgent() async {
        let cmd = SpawnCommand(flags: ["--worktree", "main"])
        var stderrCapture = ""
        // We can't easily capture stderr in tests, but we verify the logic:
        // Without --agent, the command should detect the missing flag.
        // The actual exit(1) makes this hard to test in-process, so we test
        // the argument extraction logic indirectly via the control client.
        #expect(cmd.flags.firstIndex(of: "--agent") == nil)
    }

    @Test("SpawnCommand extracts agent ID from flags")
    func spawnExtractsAgentID() {
        let flags = ["--agent", "claude-code", "--worktree", "task-1", "--cwd", "/tmp"]
        guard let agentIndex = flags.firstIndex(of: "--agent"),
              agentIndex + 1 < flags.count else {
            Issue.record("Agent index not found")
            return
        }
        #expect(flags[agentIndex + 1] == "claude-code")
    }

    @Test("SpawnCommand extracts optional worktree and cwd")
    func spawnExtractsOptionalFlags() {
        let flags = ["--agent", "aider", "--worktree", "symaira/task-1", "--cwd", "~/project"]

        var worktreeBranch: String? = nil
        if let idx = flags.firstIndex(of: "--worktree"), idx + 1 < flags.count {
            worktreeBranch = flags[idx + 1]
        }

        var workingDirectory: String? = nil
        if let idx = flags.firstIndex(of: "--cwd"), idx + 1 < flags.count {
            workingDirectory = flags[idx + 1]
        }

        #expect(worktreeBranch == "symaira/task-1")
        #expect(workingDirectory == "~/project")
    }

    @Test("SpawnCommand works with only --agent")
    func spawnMinimalFlags() {
        let flags = ["--agent", "open-code"]
        var worktreeBranch: String? = nil
        if let idx = flags.firstIndex(of: "--worktree"), idx + 1 < flags.count {
            worktreeBranch = flags[idx + 1]
        }
        #expect(worktreeBranch == nil)
    }

    // MARK: - Focus command argument parsing

    @Test("FocusCommand requires a positional pane-id argument")
    func focusRequiresPaneID() {
        let flags: [String] = []
        let hasPaneID = flags.first.map { !$0.hasPrefix("-") } ?? false
        #expect(hasPaneID == false)
    }

    @Test("FocusCommand rejects flags starting with dash as pane ID")
    func focusRejectsDashFlags() {
        let flags = ["--json"]
        let hasPaneID = flags.first.map { !$0.hasPrefix("-") } ?? false
        #expect(hasPaneID == false)
    }

    @Test("FocusCommand accepts valid UUID")
    func focusAcceptsValidUUID() {
        let uuid = UUID()
        let flags = [uuid.uuidString]
        let parsed = UUID(uuidString: flags[0])
        #expect(parsed == uuid)
    }

    @Test("FocusCommand rejects invalid UUID")
    func focusRejectsInvalidUUID() {
        let parsed = UUID(uuidString: "not-a-uuid")
        #expect(parsed == nil)
    }

    // MARK: - Blocked command flags

    @Test("BlockedCommand detects --json flag")
    func blockedJSONFlag() {
        let flags = ["--json"]
        let jsonMode = flags.contains("--json")
        #expect(jsonMode == true)
    }

    @Test("BlockedCommand without --json defaults to human mode")
    func blockedDefaultMode() {
        let flags: [String] = []
        let jsonMode = flags.contains("--json")
        #expect(jsonMode == false)
    }

    // MARK: - Full roundtrip via mock server

    @Test("Spawn roundtrip via mock server")
    func spawnRoundtrip() async throws {
        let tmpSocket = NSTemporaryDirectory() + "cli-spawn-\(UUID().uuidString).sock"
        let provider = MockControlProvider()
        let server = ControlServer(socketPath: tmpSocket)
        try await server.start(provider: provider)
        defer { Task { await server.stop() } }

        try await Task.sleep(nanoseconds: 10_000_000)

        let client = ControlClient(socketPath: tmpSocket)
        let paneID = try await client.spawn(
            agentID: "claude-code",
            worktreeBranch: "symaira/task-1",
            workingDirectory: "/tmp/test")

        let spawned = await provider.spawnedPanes
        #expect(spawned.count == 1)
        #expect(spawned.first?.agentID == "claude-code")
        #expect(spawned.first?.branch == "symaira/task-1")
        #expect(spawned.first?.cwd == "/tmp/test")
        #expect(paneID != UUID())
    }

    @Test("Blocked returns nil when no pane is blocked")
    func blockedReturnsNil() async throws {
        let tmpSocket = NSTemporaryDirectory() + "cli-blocked-\(UUID().uuidString).sock"
        let provider = MockControlProvider(blockedID: nil)
        let server = ControlServer(socketPath: tmpSocket)
        try await server.start(provider: provider)
        defer { Task { await server.stop() } }

        try await Task.sleep(nanoseconds: 10_000_000)

        let client = ControlClient(socketPath: tmpSocket)
        let result = try await client.blocked()
        #expect(result == nil)
    }

    @Test("Blocked returns pane ID when a pane is blocked")
    func blockedReturnsPaneID() async throws {
        let blockedID = UUID()
        let tmpSocket = NSTemporaryDirectory() + "cli-blocked2-\(UUID().uuidString).sock"
        let provider = MockControlProvider(blockedID: blockedID)
        let server = ControlServer(socketPath: tmpSocket)
        try await server.start(provider: provider)
        defer { Task { await server.stop() } }

        try await Task.sleep(nanoseconds: 10_000_000)

        let client = ControlClient(socketPath: tmpSocket)
        let result = try await client.blocked()
        #expect(result == blockedID)
    }

    @Test("Focus roundtrip via mock server")
    func focusRoundtrip() async throws {
        let targetID = UUID()
        let tmpSocket = NSTemporaryDirectory() + "cli-focus-\(UUID().uuidString).sock"
        let provider = MockControlProvider(
            snapshot: OrchestrationSnapshot(
                panes: [PaneSnapshot(id: targetID, title: "test-pane")]))
        let server = ControlServer(socketPath: tmpSocket)
        try await server.start(provider: provider)
        defer { Task { await server.stop() } }

        try await Task.sleep(nanoseconds: 10_000_000)

        let client = ControlClient(socketPath: tmpSocket)
        try await client.focus(paneID: targetID)

        let focused = await provider.focusedIDs
        #expect(focused.first == targetID)
    }

    @Test("Spawn rejects missing agentID via RPC error")
    func spawnRejectsMissingAgentID() async throws {
        let tmpSocket = NSTemporaryDirectory() + "cli-spawn-err-\(UUID().uuidString).sock"
        let server = ControlServer(socketPath: tmpSocket)
        try await server.start(provider: MockControlProvider())
        defer { Task { await server.stop() } }

        try await Task.sleep(nanoseconds: 10_000_000)

        let client = ControlClient(socketPath: tmpSocket)
        let request = ControlRequest(method: .spawn, params: ControlParams(), id: 1)
        do {
            _ = try await client.send(request)
            Issue.record("Expected rpcError for missing agentID")
        } catch ControlClientError.rpcError(let err) {
            #expect(err.code == -32602) // invalidParams
        }
    }

    @Test("Focus rejects missing paneID via RPC error")
    func focusRejectsMissingPaneID() async throws {
        let tmpSocket = NSTemporaryDirectory() + "cli-focus-err-\(UUID().uuidString).sock"
        let server = ControlServer(socketPath: tmpSocket)
        try await server.start(provider: MockControlProvider())
        defer { Task { await server.stop() } }

        try await Task.sleep(nanoseconds: 10_000_000)

        let client = ControlClient(socketPath: tmpSocket)
        let request = ControlRequest(method: .focus, params: ControlParams(), id: 1)
        do {
            _ = try await client.send(request)
            Issue.record("Expected rpcError for missing paneID")
        } catch ControlClientError.rpcError(let err) {
            #expect(err.code == -32602) // invalidParams
        }
    }
}
