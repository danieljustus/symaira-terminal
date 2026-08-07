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
        let params = ControlParams(paneID: paneID, lines: lines)
        let body = try await send(.init(method: .readScrollback, params: params))
        return ScrollbackResult(paneID: paneID, lines: body.scrollbackLines ?? [])
    }

    public func requestOpenTab(command: String) async throws -> TabRequestResult {
        TabRequestResult(requestID: UUID(), status: "not_supported")
    }

    // MARK: - Transport

    /// Timeout for connect/read/write on the control socket. Bounds every call:
    /// a silent or wedged server yields `noResponse` instead of a hang.
    private static let ioTimeoutSeconds = 5

    /// Opens a connection, writes the request, reads the response, closes.
    ///
    /// The blocking syscalls run on a dedicated detached thread — never on the
    /// cooperative Swift Concurrency pool (which they would starve) and never
    /// via GCD (whose worker queues can stall when the runner's dispatch/XPC
    /// environment is degraded — see issue #347: the ControlKit test suite
    /// wedged for ~52 min on the self-hosted runner).
    ///
    /// Thread bound (issue #354): exactly one detached thread per in-flight
    /// request and no more. Each thread runs a single request end-to-end —
    /// bounded by `ioTimeoutSeconds` on connect/read/write — and exits, so the
    /// concurrent thread count equals the number of concurrent `send` calls,
    /// which the caller controls. The server-side read loop, by contrast,
    /// previously spawned one thread per received chunk; it is bounded by a
    /// persistent per-connection reader thread (see `BlockingSocketIO` in
    /// LineDelimitedJSONServer.swift).
    public func send(_ request: ControlRequest) async throws -> ControlResponseBody {
        let path = socketPath
        return try await withCheckedThrowingContinuation { cont in
            Thread.detachNewThread {
                cont.resume(with: Result { try Self.sendBlocking(request, socketPath: path) })
            }
        }
    }

    private static func sendBlocking(
        _ request: ControlRequest, socketPath: String
    ) throws -> ControlResponseBody {
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
        // Bounded connect: AF_UNIX connect() to a wedged listener can block
        // indefinitely (backlog full). Non-blocking connect + poll() bounds it
        // by the same ioTimeout as read/write (issue #347 hang protection).
        let flags = Darwin.fcntl(fd, F_GETFL, 0)
        _ = Darwin.fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        let connectResult = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if connectResult != 0 {
            // Defensive branch (issue #355): on Darwin, AF_UNIX connect()
            // never reports EINPROGRESS — a full listen backlog is refused
            // synchronously with ECONNREFUSED (blocking and non-blocking
            // alike) and a missing path fails with ENOENT, so this branch is
            // unreachable for the current transport. It is kept so a connect
            // that genuinely stays in progress (e.g. if the transport ever
            // gains a TCP path) is still bounded by ioTimeoutSeconds instead
            // of hanging (issue #347 hang protection). The poll()/getsockopt
            // machinery is exercised directly by tests via
            // `finishBoundedConnect`.
            guard errno == EINPROGRESS else {
                _ = Darwin.fcntl(fd, F_SETFL, flags)
                throw ControlClientError.connectionRefused
            }
            _ = Darwin.fcntl(fd, F_SETFL, flags)
            try Self.finishBoundedConnect(
                fd: fd, timeoutMilliseconds: Int32(ioTimeoutSeconds) * 1000)
        } else {
            _ = Darwin.fcntl(fd, F_SETFL, flags)
        }

        var timeout = timeval(tv_sec: ioTimeoutSeconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

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

    /// Completes a non-blocking connect: waits for writability with poll(),
    /// then reads SO_ERROR to distinguish "connected" from "refused while in
    /// progress". Throws `noResponse` on poll timeout and `connectionRefused`
    /// when the pending connect failed.
    ///
    /// Internal (not public) so tests can drive the poll()/getsockopt()
    /// machinery on real file descriptors (issue #355): the EINPROGRESS
    /// branch of `sendBlocking` is unreachable on Darwin for AF_UNIX sockets,
    /// so the seam lets the bounded-connect logic be exercised directly.
    static func finishBoundedConnect(fd: Int32, timeoutMilliseconds: Int32) throws {
        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let pollResult = Darwin.poll(&pfd, 1, timeoutMilliseconds)
        guard pollResult > 0 else { throw ControlClientError.noResponse }
        // Distinguish "connected" from "refused while in progress".
        var socketError: Int32 = 0
        var errorLength = socklen_t(MemoryLayout<Int32>.size)
        let errResult = Darwin.getsockopt(
            fd, SOL_SOCKET, SO_ERROR, &socketError, &errorLength)
        guard errResult == 0, socketError == 0 else {
            throw ControlClientError.connectionRefused
        }
    }
}
