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
public struct ControlClient: Sendable {

    public let socketPath: String
    private var requestID: Int = 1

    public init(socketPath: String = ControlServer.defaultSocketPath) {
        self.socketPath = socketPath
    }

    // MARK: - Read verbs

    public func snapshot() async throws -> OrchestrationSnapshot {
        let result = try await send(.init(method: .snapshot))
        guard case .snapshot(let v) = result else { throw ControlClientError.noResponse }
        return v
    }

    public func panes() async throws -> [PaneSnapshot] {
        let result = try await send(.init(method: .panes))
        guard case .panes(let v) = result else { throw ControlClientError.noResponse }
        return v
    }

    public func pendingApprovals() async throws -> [ApprovalSummary] {
        let result = try await send(.init(method: .pendingApprovals))
        guard case .approvals(let v) = result else { throw ControlClientError.noResponse }
        return v
    }

    public func worktrees() async throws -> [WorktreeSnapshot] {
        let result = try await send(.init(method: .worktrees))
        guard case .worktrees(let v) = result else { throw ControlClientError.noResponse }
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
        let result = try await send(.init(method: .spawn, params: params))
        guard case .spawned(let id) = result else { throw ControlClientError.noResponse }
        return id
    }

    public func focus(paneID: UUID) async throws {
        let params = ControlParams(paneID: paneID)
        _ = try await send(.init(method: .focus, params: params))
    }

    public func blocked() async throws -> UUID? {
        let result = try await send(.init(method: .blocked))
        guard case .blocked(let id) = result else { throw ControlClientError.noResponse }
        return id
    }

    // MARK: - Transport

    /// Opens a connection, writes the request, reads the response, closes.
    public func send(_ request: ControlRequest) async throws -> ControlResult {
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
        var buf = [UInt8](repeating: 0, count: 4096)
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
