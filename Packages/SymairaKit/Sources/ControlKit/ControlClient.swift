import AgentKit
import Darwin
import Foundation

/// Connects to a running Symaira Terminal instance via the control socket and
/// sends JSON-RPC 2.0 requests, returning typed response bodies.
///
/// Usage:
///
///     let client = ControlClient()
///     let snapshot = try await client.snapshot()
///
/// `ControlClient` is a value type; each method call opens and closes its own
/// connection. For repeated calls, reuse the same instance (connections are
/// stateless from the server's perspective).
public struct ControlClient: Sendable, OrchestrationControlProvider {

    public let socketPath: String
    private var requestID: Int = 1

    public init(socketPath: String = ControlServer.defaultSocketPath) {
        self.socketPath = socketPath
    }

    // MARK: - Read verbs

    public func snapshot() async throws -> OrchestrationSnapshot {
        let body = try await send(.init(method: .snapshot))
        guard let v = body.snapshot else { throw ControlClientError.noResponse }
        return v
    }

    public func panes() async throws -> [PaneSnapshot] {
        let body = try await send(.init(method: .panes))
        guard let v = body.panes else { throw ControlClientError.noResponse }
        return v
    }

    public func pendingApprovals() async throws -> [ApprovalSummary] {
        let body = try await send(.init(method: .pendingApprovals))
        guard let v = body.approvals else { throw ControlClientError.noResponse }
        return v
    }

    public func worktrees() async throws -> [WorktreeSnapshot] {
        let body = try await send(.init(method: .worktrees))
        guard let v = body.worktrees else { throw ControlClientError.noResponse }
        return v
    }

    // MARK: - Write verbs

    public func spawn(
        agentID: String,
        worktreeBranch: String? = nil,
        workingDirectory: String? = nil
    ) async throws -> UUID {
        let params = ControlParams(
            agentID: agentID,
            worktreeBranch: worktreeBranch,
            workingDirectory: workingDirectory)
        let body = try await send(.init(method: .spawn, params: params))
        guard let id = body.spawnedPaneID else { throw ControlClientError.noResponse }
        return id
    }

    public func focus(paneID: UUID) async throws {
        let params = ControlParams(paneID: paneID)
        _ = try await send(.init(method: .focus, params: params))
    }

    public func blocked() async throws -> UUID? {
        let body = try await send(.init(method: .blocked))
        return body.blockedPaneID
    }

    public func readScrollback(paneID: UUID?, lines: Int = 200) async throws -> ScrollbackResult {
        let params = ControlParams(paneID: paneID)
        let body = try await send(.init(method: .readScrollback, params: params))
        return ScrollbackResult(paneID: paneID, lines: body.scrollbackLines ?? [])
    }

    public func requestOpenTab(command: String) async throws -> TabRequestResult {
        TabRequestResult(requestID: UUID(), status: "not_supported")
    }

    // MARK: - Transport

    /// Opens a connection, writes the request, reads the response, closes.
    public func send(_ request: ControlRequest) async throws -> ControlResponseBody {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ControlClientError.notConnected }
        defer { Darwin.close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
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
        guard connectResult == 0 else { throw ControlClientError.connectionRefused }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var payload = try encoder.encode(request)
        payload.append(0x0a)
        guard payload.withUnsafeBytes({ Darwin.write(fd, $0.baseAddress!, payload.count) }) == payload.count
        else { throw ControlClientError.notConnected }

        // Read until we get a complete line
        var incoming = Data()
        var buf = [UInt8](repeating: 0, count: 65_536)
        while !incoming.contains(0x0a) {
            let n = buf.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!, $0.count) }
            guard n > 0 else { break }
            incoming.append(contentsOf: buf.prefix(n))
        }
        guard let nlIdx = incoming.firstIndex(of: 0x0a) else { throw ControlClientError.noResponse }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(ControlResponse.self, from: incoming[incoming.startIndex..<nlIdx])

        if let error = response.error { throw ControlClientError.rpcError(error) }
        guard let body = response.result else { throw ControlClientError.noResponse }
        return body
    }
}

// MARK: - Persistent Connection Client

/// A connection-per-call client that optionally maintains a persistent socket
/// for multi-call MCP tools, avoiding repeated bind/connect/teardown cycles.
///
/// Usage:
///
///     let client = try await PersistentControlClient.connect(socketPath: path)
///     let snapshot = try await client.snapshot()
///     let panes = try await client.panes()
///     await client.close()
///
public actor PersistentControlClient {
    private let socketPath: String
    private var fd: Int32 = -1
    private var requestID: Int = 1
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init(socketPath: String) {
        self.socketPath = socketPath
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    /// Create a connected client. The connection is established during creation.
    public static func connect(
        socketPath: String = ControlServer.defaultSocketPath
    ) async throws -> PersistentControlClient {
        let client = PersistentControlClient(socketPath: socketPath)
        try await client.connect()
        return client
    }

    deinit {
        if fd >= 0 { Darwin.close(fd) }
    }

    private func connect() throws {
        fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ControlClientError.notConnected }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        withUnsafeMutableBytes(of: &addr.sun_path) { ptr in
            for (i, b) in pathBytes.prefix(ptr.count - 1).enumerated() {
                ptr[i] = UInt8(bitPattern: b)
            }
        }
        let result = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            Darwin.close(fd)
            fd = -1
            throw ControlClientError.connectionRefused
        }
    }

    private func ensureConnected() throws {
        if fd < 0 { try connect() }
    }

    /// Close the persistent connection. Idempotent.
    public func close() {
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
    }

    // MARK: - Read verbs

    public func snapshot() async throws -> OrchestrationSnapshot {
        let body = try await send(.init(method: .snapshot))
        guard let v = body.snapshot else { throw ControlClientError.noResponse }
        return v
    }

    public func panes() async throws -> [PaneSnapshot] {
        let body = try await send(.init(method: .panes))
        guard let v = body.panes else { throw ControlClientError.noResponse }
        return v
    }

    public func pendingApprovals() async throws -> [ApprovalSummary] {
        let body = try await send(.init(method: .pendingApprovals))
        guard let v = body.approvals else { throw ControlClientError.noResponse }
        return v
    }

    public func worktrees() async throws -> [WorktreeSnapshot] {
        let body = try await send(.init(method: .worktrees))
        guard let v = body.worktrees else { throw ControlClientError.noResponse }
        return v
    }

    // MARK: - Write verbs

    public func spawn(
        agentID: String,
        worktreeBranch: String? = nil,
        workingDirectory: String? = nil
    ) async throws -> UUID {
        let params = ControlParams(
            agentID: agentID,
            worktreeBranch: worktreeBranch,
            workingDirectory: workingDirectory)
        let body = try await send(.init(method: .spawn, params: params))
        guard let id = body.spawnedPaneID else { throw ControlClientError.noResponse }
        return id
    }

    public func focus(paneID: UUID) async throws {
        let params = ControlParams(paneID: paneID)
        _ = try await send(.init(method: .focus, params: params))
    }

    public func blocked() async throws -> UUID? {
        let body = try await send(.init(method: .blocked))
        return body.blockedPaneID
    }

    public func readScrollback(paneID: UUID?, lines: Int = 200) async throws -> ScrollbackResult {
        let params = ControlParams(paneID: paneID)
        let body = try await send(.init(method: .readScrollback, params: params))
        return ScrollbackResult(paneID: paneID, lines: body.scrollbackLines ?? [])
    }

    public func requestOpenTab(command: String) async throws -> TabRequestResult {
        TabRequestResult(requestID: UUID(), status: "not_supported")
    }

    // MARK: - Transport

    private func send(_ request: ControlRequest) async throws -> ControlResponseBody {
        try ensureConnected()

        var payload = try encoder.encode(request)
        payload.append(0x0a)
        guard payload.withUnsafeBytes({ Darwin.write(fd, $0.baseAddress!, payload.count) }) == payload.count
        else {
            close()
            throw ControlClientError.notConnected
        }

        var incoming = Data()
        var buf = [UInt8](repeating: 0, count: 65_536)
        while !incoming.contains(0x0a) {
            let n = buf.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!, $0.count) }
            guard n > 0 else {
                close()
                break
            }
            incoming.append(contentsOf: buf.prefix(n))
        }
        guard let nlIdx = incoming.firstIndex(of: 0x0a) else { throw ControlClientError.noResponse }

        let response = try decoder.decode(ControlResponse.self, from: incoming[incoming.startIndex..<nlIdx])

        if let error = response.error { throw ControlClientError.rpcError(error) }
        guard let body = response.result else { throw ControlClientError.noResponse }
        return body
    }
}
