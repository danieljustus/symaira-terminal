import ControlKit
import Darwin
import Foundation
import TerminalCore

enum MCPStdioError: Error, Sendable {
    case encodingFailed
    case connectionFailed(String)
}

public actor MCPStdioServer {
    private let client: ControlClient
    private static let maxFrameSize = 1_048_576

    public init(client: ControlClient = ControlClient()) {
        self.client = client
    }

    public func run() async {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let dispatcher = MCPToolDispatcher(provider: client)

        var pending = Data()
        var buf = [UInt8](repeating: 0, count: 65_536)

        while !Task.isCancelled {
            let n = buf.withUnsafeMutableBytes { Darwin.read(STDIN_FILENO, $0.baseAddress!, $0.count) }
            guard n > 0 else { break }
            pending.append(contentsOf: buf.prefix(n))

            if pending.count > Self.maxFrameSize {
                let errorResponse = MCPResponse(
                    id: nil,
                    error: MCPError(code: -32600, message: "Frame too large"))
                writeResponse(errorResponse, encoder: encoder)
                break
            }

            while let nlIdx = pending.firstIndex(of: 0x0a) {
                let line = Data(pending[pending.startIndex..<nlIdx])
                pending.removeSubrange(pending.startIndex...nlIdx)
                guard !line.isEmpty else { continue }

                let response = await dispatch(line: line, decoder: decoder, dispatcher: dispatcher)
                writeResponse(response, encoder: encoder)
            }
        }
    }

    private func dispatch(line: Data, decoder: JSONDecoder, dispatcher: MCPToolDispatcher) async -> MCPResponse {
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

    private func handle(request: MCPRequest, dispatcher: MCPToolDispatcher) async throws -> MCPResult {
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

    private func writeResponse(_ response: MCPResponse, encoder: JSONEncoder) {
        guard var data = try? encoder.encode(response) else { return }
        data.append(0x0a)
        data.withUnsafeBytes { _ = Darwin.write(STDOUT_FILENO, $0.baseAddress!, data.count) }
    }
}
