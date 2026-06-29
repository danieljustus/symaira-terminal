import ControlKit
import Darwin
import Foundation
import TerminalCore

// MARK: - MCPServer

/// A local Unix domain socket MCP server that exposes terminal tools to AI agents.
///
/// The server speaks JSON-RPC 2.0 over a line-delimited stream, implementing the
/// Model Context Protocol (MCP) `initialize`, `tools/list`, and `tools/call` methods.
///
/// Socket path: `~/Library/Application Support/Symaira Terminal/mcp.sock` (0600).
/// Only processes running as the same user can connect.
///
/// ## Usage
/// ```swift
/// let server = MCPServer()
/// try await server.start(provider: myControlProvider)
/// // ... on app termination:
/// await server.stop()
/// ```
///
/// ## Security
/// - Socket permissions are set to 0600; remote access is not possible.
/// - `requestOpenTab` always routes through the approval queue in the UI — the shell
///   command is never executed without explicit user confirmation.
/// - Frame size is limited to 1 MiB; idle connections time out after 30 s.
public actor MCPServer: LineDelimitedJSONServer {

    // MARK: - Limits

    public let maxFrameSize = 1_048_576
    public let idleTimeoutSeconds: Int = 30
    public static let maxConcurrentConnections = 16

    /// Default socket path inside the app's Application Support directory.
    public static var defaultSocketPath: String {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Symaira Terminal/mcp.sock").path
    }

    public let socketPath: String
    private let socketServer: UnixSocketServer
    private var provider: (any OrchestrationControlProvider)?

    public init(socketPath: String = MCPServer.defaultSocketPath) {
        self.socketPath = socketPath
        self.socketServer = UnixSocketServer(socketPath: socketPath)
    }

    // MARK: - Lifecycle

    /// Bind the socket, enforce 0600 permissions, and begin accepting connections.
    ///
    /// - Parameter provider: The app-supplied ``OrchestrationControlProvider`` that backs
    ///   the MCP tool implementations.
    public func start(provider: some OrchestrationControlProvider) throws {
        self.provider = provider
        try socketServer.start()
        let server = socketServer
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        Task.detached { [self] in
            await server.acceptLoop(
                maxConcurrentConnections: Self.maxConcurrentConnections
            ) { clientFD in
                await self.handleConnection(fd: clientFD, encoder: encoder, decoder: decoder)
            }
        }
    }

    /// Tear down the socket and cancel the accept loop. Idempotent.
    public func stop() {
        socketServer.stop()
    }

    // MARK: - LineDelimitedJSONServer

    public nonisolated func dispatch(line: Data, decoder: JSONDecoder) async -> MCPResponse {
        do {
            let request = try decoder.decode(MCPRequest.self, from: line)
            let result = try await handle(request: request)
            return MCPResponse(id: request.id, result: result)
        } catch let e as MCPDispatchError {
            switch e {
            case .unknownTool(let name):
                return MCPResponse(
                    id: nil,
                    error: MCPError(code: -32601, message: "Unknown tool: \(name)"))
            case .missingRequired(let param):
                return MCPResponse(
                    id: nil,
                    error: MCPError(code: -32602, message: "Missing required parameter: \(param)"))
            }
        } catch {
            return MCPResponse(
                id: nil,
                error: MCPError(code: -32700, message: "Parse error: \(error)"))
        }
    }

    public nonisolated func makeErrorResponse(message: String) -> MCPResponse {
        MCPResponse(error: .init(code: -32600, message: message))
    }

    // MARK: - Dispatch

    private func handle(request: MCPRequest) async throws -> MCPResult {
        guard let provider else {
            throw MCPDispatchError.unknownTool("server not started")
        }
        let dispatcher = MCPToolDispatcher(provider: provider)
        switch request.method {
        case "initialize":
            return MCPResult(
                protocolVersion: "2024-11-05",
                capabilities: MCPCapabilities(tools: MCPToolsCapability(listChanged: false)),
                serverInfo: MCPServerInfo(
                    name: "symaira-terminal",
                    version: SymairaVersion.current))

        case "notifications/initialized":
            return MCPResult()

        case "tools/list":
            return MCPResult(tools: MCPTool.allCases.map(\.definition))

        case "tools/call":
            guard let name = request.params?.name else {
                throw MCPDispatchError.missingRequired("name")
            }
            return try await dispatcher.call(name: name, arguments: request.params?.arguments)

        case "ping":
            return MCPResult()

        default:
            throw MCPDispatchError.unknownTool(request.method)
        }
    }

    func handleForTest(
        request: MCPRequest,
        dispatcher: MCPToolDispatcher
    ) async throws -> MCPResult {
        self.provider = dispatcher.provider
        return try await handle(request: request)
    }
}
