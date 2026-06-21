import ControlKit
import Darwin
import Foundation

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
public actor MCPServer {

    // MARK: - Limits

    public static let maxFrameSize = 1_048_576
    public static let idleTimeoutSeconds: Int = 30
    public static let maxConcurrentConnections = 16

    /// Default socket path inside the app's Application Support directory.
    public static var defaultSocketPath: String {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Symaira Terminal/mcp.sock").path
    }

    public let socketPath: String
    private let socketServer: UnixSocketServer

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
        try socketServer.start()
        let server = socketServer
        Task.detached {
            await server.acceptLoop(
                maxConcurrentConnections: Self.maxConcurrentConnections
            ) { clientFD in
                await Self.handleConnection(fd: clientFD, provider: provider)
            }
        }
    }

    /// Tear down the socket and cancel the accept loop. Idempotent.
    public func stop() {
        socketServer.stop()
    }

    private static func handleConnection(
        fd: Int32,
        provider: some OrchestrationControlProvider
    ) async {
        defer { Darwin.close(fd) }

        var timeout = timeval(tv_sec: idleTimeoutSeconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        let dispatcher = MCPToolDispatcher(provider: provider)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()

        var pending = Data()
        var buf = [UInt8](repeating: 0, count: 4096)

        while !Task.isCancelled {
            let n = buf.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!, $0.count) }
            guard n > 0 else { break }
            pending.append(contentsOf: buf.prefix(n))

            if pending.count > maxFrameSize {
                writeResponse(
                    MCPResponse(error: .init(code: -32600, message: "Frame too large")),
                    fd: fd, encoder: encoder)
                break
            }

            while let nlIdx = pending.firstIndex(of: 0x0a) {
                let line = Data(pending[pending.startIndex..<nlIdx])
                pending.removeSubrange(pending.startIndex...nlIdx)
                guard !line.isEmpty else { continue }

                let response = await dispatch(line: line, dispatcher: dispatcher, decoder: decoder)
                writeResponse(response, fd: fd, encoder: encoder)
            }
        }
    }

    // MARK: - Dispatch

    private static func dispatch(
        line: Data,
        dispatcher: MCPToolDispatcher,
        decoder: JSONDecoder
    ) async -> MCPResponse {
        do {
            let request = try decoder.decode(MCPRequest.self, from: line)
            let result = try await handle(request: request, dispatcher: dispatcher)
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

    private static func handle(
        request: MCPRequest,
        dispatcher: MCPToolDispatcher
    ) async throws -> MCPResult {
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

    static func handleForTest(
        request: MCPRequest,
        dispatcher: MCPToolDispatcher
    ) async throws -> MCPResult {
        try await handle(request: request, dispatcher: dispatcher)
    }

    // MARK: - Write helper

    private static func writeResponse(_ response: MCPResponse, fd: Int32, encoder: JSONEncoder) {
        guard var data = try? encoder.encode(response) else { return }
        data.append(0x0a) // newline delimiter
        data.withUnsafeBytes { _ = Darwin.write(fd, $0.baseAddress!, $0.count) }
    }
}
