import ControlKit
import Darwin
import Foundation

enum MCPStdioError: Error, Sendable {
    case encodingFailed
    case connectionFailed(String)
}

actor MCPStdioServer {
    private let client: ControlClient

    init(client: ControlClient = ControlClient()) {
        self.client = client
    }

    func run() async {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        var pending = Data()
        var buf = [UInt8](repeating: 0, count: 4096)

        while !Task.isCancelled {
            let n = buf.withUnsafeMutableBytes { Darwin.read(STDIN_FILENO, $0.baseAddress!, $0.count) }
            guard n > 0 else { break }
            pending.append(contentsOf: buf.prefix(n))

            while let nlIdx = pending.firstIndex(of: 0x0a) {
                let line = Data(pending[pending.startIndex..<nlIdx])
                pending.removeSubrange(pending.startIndex...nlIdx)
                guard !line.isEmpty else { continue }

                let response = await dispatch(line: line, decoder: decoder)
                writeResponse(response, encoder: encoder)
            }
        }
    }

    private func dispatch(line: Data, decoder: JSONDecoder) async -> MCPResponse {
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

    private func handle(request: MCPRequest) async throws -> MCPResult {
        switch request.method {
        case "initialize":
            return MCPResult(
                protocolVersion: "2024-11-05",
                capabilities: MCPCapabilities(tools: MCPToolsCapability(listChanged: false)),
                serverInfo: MCPServerInfo(
                    name: "symaira-terminal",
                    version: "1.0.0"))

        case "notifications/initialized":
            return MCPResult()

        case "tools/list":
            return MCPResult(tools: MCPTool.allCases.map(\.definition))

        case "tools/call":
            guard let name = request.params?.name else {
                throw MCPDispatchError.missingRequired("name")
            }
            return try await dispatchToolCall(name: name, arguments: request.params?.arguments)

        case "ping":
            return MCPResult()

        default:
            throw MCPDispatchError.unknownTool(request.method)
        }
    }

    private func dispatchToolCall(name: String, arguments: [String: AnyCodable]?) async throws -> MCPResult {
        guard let tool = MCPTool(rawValue: name) else {
            throw MCPDispatchError.unknownTool(name)
        }
        switch tool {
        case .listAgents:
            let snapshot = try await client.snapshot()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            let text = String(data: data, encoding: .utf8) ?? "{}"
            return MCPResult(content: [MCPContent(type: "text", text: text)], isError: false)

        case .readPaneOutput:
            var lines = 200
            if let raw = arguments?["lines"]?.value {
                switch raw {
                case let i as Int:    lines = max(1, min(i, 10_000))
                case let d as Double: lines = max(1, min(Int(d), 10_000))
                default: break
                }
            }
            var paneID: UUID?
            if let raw = arguments?["pane_id"]?.value as? String {
                paneID = UUID(uuidString: raw)
            }
            let panes = try await client.panes()
            if let pid = paneID, !panes.contains(where: { $0.id == pid }) {
                return MCPResult(
                    content: [MCPContent(type: "text", text: "Pane not found: \(pid.uuidString)")],
                    isError: true)
            }
            let snapshot = try await client.snapshot()
            let allLines = snapshot.panes.flatMap { _ -> [String] in [] }
            let text = allLines.isEmpty ? "(no output)" : allLines.suffix(lines).joined(separator: "\n")
            return MCPResult(content: [MCPContent(type: "text", text: text)], isError: false)

        case .getPendingApprovals:
            let approvals = try await client.pendingApprovals()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(approvals)
            let text = String(data: data, encoding: .utf8) ?? "[]"
            return MCPResult(content: [MCPContent(type: "text", text: text)], isError: false)

        case .spawn:
            guard let agentID = arguments?["agent_id"]?.value as? String, !agentID.isEmpty else {
                throw MCPDispatchError.missingRequired("agent_id")
            }
            var worktreeBranch: String?
            if let raw = arguments?["worktree_branch"]?.value as? String {
                worktreeBranch = raw
            }
            var workingDirectory: String?
            if let raw = arguments?["working_directory"]?.value as? String {
                workingDirectory = raw
            }
            let paneID = try await client.spawn(
                agentID: agentID,
                worktreeBranch: worktreeBranch,
                workingDirectory: workingDirectory)
            let text = "Spawned pane \(paneID.uuidString) running '\(agentID)'."
            return MCPResult(content: [MCPContent(type: "text", text: text)], isError: false)

        case .focus:
            guard let rawID = arguments?["pane_id"]?.value as? String else {
                throw MCPDispatchError.missingRequired("pane_id")
            }
            guard let paneID = UUID(uuidString: rawID) else {
                return MCPResult(
                    content: [MCPContent(type: "text", text: "Invalid UUID: \(rawID)")],
                    isError: true)
            }
            try await client.focus(paneID: paneID)
            let text = "Focused pane \(paneID.uuidString)."
            return MCPResult(content: [MCPContent(type: "text", text: text)], isError: false)

        case .blocked:
            let blockedID = try await client.blocked()
            let text: String
            if let id = blockedID {
                text = "{\"paneID\": \"\(id.uuidString)\"}"
            } else {
                text = "{}"
            }
            return MCPResult(content: [MCPContent(type: "text", text: text)], isError: false)
        }
    }

    private func writeResponse(_ response: MCPResponse, encoder: JSONEncoder) {
        guard var data = try? encoder.encode(response) else { return }
        data.append(0x0a)
        data.withUnsafeBytes { _ = Darwin.write(STDOUT_FILENO, $0.baseAddress!, data.count) }
    }
}
