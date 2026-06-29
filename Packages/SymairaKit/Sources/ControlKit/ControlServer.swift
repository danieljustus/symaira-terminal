import Darwin
import Foundation

/// Binds the control surface Unix domain socket and dispatches JSON-RPC 2.0 requests
/// to an `OrchestrationControlProvider` implementation supplied by the App.
///
/// The server owns the socket lifecycle. Call `start(provider:)` once at app startup
/// and `stop()` on termination. It is safe to call `stop()` without a prior `start()`.
///
/// Transport details: ADR-002 and docs/design/agent-control-surface.md.
public actor ControlServer: LineDelimitedJSONServer {

    // MARK: - Security limits

    /// Maximum frame size in bytes (1 MiB). Oversized frames are rejected with a JSON-RPC error.
    public let maxFrameSize = 1_048_576

    /// Idle timeout in seconds. Connections with no data for this duration are closed.
    public let idleTimeoutSeconds: Int = 30

    /// Maximum concurrent connections. New connections are rejected when at cap.
    public static let maxConcurrentConnections = 16

    public static var defaultSocketPath: String {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Symaira Terminal/control.sock").path
    }

    public let socketPath: String
    private let socketServer: UnixSocketServer
    private var provider: (any OrchestrationControlProvider)?

    public init(socketPath: String = ControlServer.defaultSocketPath) {
        self.socketPath = socketPath
        self.socketServer = UnixSocketServer(socketPath: socketPath)
    }

    /// Bind the socket, set 0600 permissions, and start accepting connections.
    public func start(provider: some OrchestrationControlProvider) throws {
        self.provider = provider
        try socketServer.start()
        let server = socketServer
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        Task.detached { [self] in
            await server.acceptLoop(maxConcurrentConnections: Self.maxConcurrentConnections) { clientFD in
                await self.handleConnection(fd: clientFD, encoder: encoder, decoder: decoder)
            }
        }
    }

    /// Close the socket and cancel the accept loop. Idempotent.
    public func stop() {
        socketServer.stop()
    }

    // MARK: - LineDelimitedJSONServer

    public nonisolated func dispatch(line: Data, decoder: JSONDecoder) async -> ControlResponse {
        do {
            let request = try decoder.decode(ControlRequest.self, from: line)
            let body = try await dispatch(request: request)
            return ControlResponse(result: body, id: request.id)
        } catch let rpcErr as ControlRPCError {
            return ControlResponse(error: rpcErr, id: nil)
        } catch {
            return ControlResponse(
                error: ControlRPCError(code: -32700, message: "Parse error: \(error)"),
                id: nil)
        }
    }

    public nonisolated func makeErrorResponse(message: String) -> ControlResponse {
        ControlResponse(
            error: ControlRPCError(code: -32600, message: message),
            id: nil)
    }

    // MARK: - Dispatch

    private func dispatch(request: ControlRequest) async throws -> ControlResponseBody {
        guard let provider else {
            throw ControlRPCError.methodNotFound
        }
        guard let method = ControlMethod(rawValue: request.method) else {
            throw ControlRPCError.methodNotFound
        }
        switch method {
        case .snapshot:
            return .of(snapshot: try await provider.snapshot())
        case .panes:
            return .of(panes: try await provider.panes())
        case .pendingApprovals:
            return .of(approvals: try await provider.pendingApprovals())
        case .worktrees:
            return .of(worktrees: try await provider.worktrees())
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
        case .readScrollback:
            let result = try await provider.readScrollback(
                paneID: request.params?.paneID,
                lines: request.params?.lines ?? 200)
            return .scrollback(result.lines)
        }
    }
}
