import Darwin
import Foundation

/// Thread-safe counter for tracking active connections across detached tasks.
private final class ConnectionCounter: @unchecked Sendable {
    private var count: Int = 0
    private let lock = NSLock()

    var current: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }

    func decrement() {
        lock.lock()
        defer { lock.unlock() }
        count -= 1
    }
}

/// Binds the control surface Unix domain socket and dispatches JSON-RPC 2.0 requests
/// to an `OrchestrationControlProvider` implementation supplied by the App.
///
/// The server owns the socket lifecycle. Call `start(provider:)` once at app startup
/// and `stop()` on termination. It is safe to call `stop()` without a prior `start()`.
///
/// Transport details: ADR-002 and docs/design/agent-control-surface.md.
public actor ControlServer {

    // MARK: - Security limits

    /// Maximum frame size in bytes (1 MiB). Oversized frames are rejected with a JSON-RPC error.
    public static let maxFrameSize = 1_048_576

    /// Idle timeout in seconds. Connections with no data for this duration are closed.
    public static let idleTimeoutSeconds: Int = 30

    /// Maximum concurrent connections. New connections are rejected when at cap.
    public static let maxConcurrentConnections = 16

    public static var defaultSocketPath: String {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Symaira Terminal/control.sock").path
    }

    public let socketPath: String
    private var serverFD: Int32 = -1
    private var acceptTask: Task<Void, Never>?
    private let connectionCounter = ConnectionCounter()

    public init(socketPath: String = ControlServer.defaultSocketPath) {
        self.socketPath = socketPath
    }

    /// Bind the socket, set 0600 permissions, and start accepting connections.
    public func start(provider: some OrchestrationControlProvider) throws {
        guard serverFD < 0 else { return }

        try? FileManager.default.removeItem(atPath: socketPath)
        let dir = (socketPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true, attributes: nil)

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ControlServerError.socketFailed(errno: errno) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        withUnsafeMutableBytes(of: &addr.sun_path) { ptr in
            for (i, b) in pathBytes.prefix(ptr.count - 1).enumerated() {
                ptr[i] = UInt8(bitPattern: b)
            }
        }
        let bindResult = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(fd)
            throw ControlServerError.bindFailed(errno: errno)
        }

        Darwin.chmod(socketPath, 0o600)

        guard Darwin.listen(fd, 16) == 0 else {
            Darwin.close(fd)
            throw ControlServerError.listenFailed(errno: errno)
        }

        serverFD = fd
        acceptTask = Task.detached { [socketPath, connectionCounter] in
            await Self.acceptLoop(
                serverFD: fd,
                socketPath: socketPath,
                provider: provider,
                counter: connectionCounter)
        }
    }

    /// Close the socket and cancel the accept loop. Idempotent.
    public func stop() {
        acceptTask?.cancel()
        acceptTask = nil
        if serverFD >= 0 {
            Darwin.close(serverFD)
            serverFD = -1
        }
        try? FileManager.default.removeItem(atPath: socketPath)
    }

    // MARK: Accept loop (runs in Task.detached — not actor-isolated)

    private static func acceptLoop(
        serverFD: Int32,
        socketPath: String,
        provider: some OrchestrationControlProvider,
        counter: ConnectionCounter
    ) async {
        while !Task.isCancelled {
            let clientFD = Darwin.accept(serverFD, nil, nil)
            guard clientFD >= 0 else { break }

            let connCount = counter.increment()
            guard connCount <= ControlServer.maxConcurrentConnections else {
                counter.decrement()
                Darwin.close(clientFD)
                continue
            }

            Task.detached {
                defer { counter.decrement() }
                await handleConnection(fd: clientFD, provider: provider)
            }
        }
    }

    private static func handleConnection(
        fd: Int32,
        provider: some OrchestrationControlProvider
    ) async {
        defer { Darwin.close(fd) }

        var timeout = timeval(tv_sec: Self.idleTimeoutSeconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        var pending = Data()
        var buf = [UInt8](repeating: 0, count: 4096)

        while !Task.isCancelled {
            let n = buf.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!, $0.count) }
            guard n > 0 else { break }
            pending.append(contentsOf: buf.prefix(n))

            if pending.count > Self.maxFrameSize {
                let errorResponse = ControlResponse(
                    error: ControlRPCError(
                        code: -32600,
                        message: "Invalid Request: frame exceeds \(Self.maxFrameSize) byte limit"),
                    id: nil)
                if var data = try? encoder.encode(errorResponse) {
                    data.append(0x0a)
                    data.withUnsafeBytes { _ = Darwin.write(fd, $0.baseAddress!, data.count) }
                }
                break
            }

            while let nlIdx = pending.firstIndex(of: 0x0a) {
                let lineSlice = pending[pending.startIndex..<nlIdx]
                pending.removeSubrange(pending.startIndex...nlIdx)
                guard !lineSlice.isEmpty else { continue }
                let line = Data(lineSlice)
                await sendResponse(
                    for: line,
                    fd: fd,
                    provider: provider,
                    decoder: decoder,
                    encoder: encoder)
            }
        }
    }

    private static func sendResponse(
        for lineData: Data,
        fd: Int32,
        provider: some OrchestrationControlProvider,
        decoder: JSONDecoder,
        encoder: JSONEncoder
    ) async {
        let response: ControlResponse
        do {
            let request = try decoder.decode(ControlRequest.self, from: lineData)
            let body = try await dispatch(request: request, provider: provider)
            response = ControlResponse(result: body, id: request.id)
        } catch let rpcErr as ControlRPCError {
            response = ControlResponse(error: rpcErr, id: nil)
        } catch {
            response = ControlResponse(
                error: ControlRPCError(code: -32700, message: "Parse error: \(error)"),
                id: nil)
        }

        if var data = try? encoder.encode(response) {
            data.append(0x0a)
            data.withUnsafeBytes { _ = Darwin.write(fd, $0.baseAddress!, data.count) }
        }
    }

    private static func dispatch(
        request: ControlRequest,
        provider: some OrchestrationControlProvider
    ) async throws -> ControlResult {
        guard let method = ControlMethod(rawValue: request.method) else {
            throw ControlRPCError.methodNotFound
        }
        switch method {
        case .snapshot:
            return .snapshot(try await provider.snapshot())
        case .panes:
            return .panes(try await provider.panes())
        case .pendingApprovals:
            return .approvals(try await provider.pendingApprovals())
        case .worktrees:
            return .worktrees(try await provider.worktrees())
        case .spawn:
            guard let agentID = request.params?.agentID else {
                throw ControlRPCError.invalidParams
            }
            let id = try await provider.spawn(
                agentID: agentID,
                worktreeBranch: request.params?.worktreeBranch,
                workingDirectory: request.params?.workingDirectory)
            return .spawned(id)
        case .focus:
            guard let paneID = request.params?.paneID else {
                throw ControlRPCError.invalidParams
            }
            try await provider.focus(paneID: paneID)
            return .focused(paneID)
        case .blocked:
            let id = try await provider.blocked()
            return .blocked(id)
        }
    }
}
