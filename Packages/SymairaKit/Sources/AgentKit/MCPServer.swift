import Foundation
import Network
import TerminalCore

/// Protocol implemented by the terminal app's PaneManager to handle MCP tool execution.
public protocol TerminalMCPDelegate: AnyObject, Sendable {
    func getActiveScrollback(lines: Int) async -> String
    func openTab(command: String) async -> Bool
}

/// JSON-RPC value representation compliant with Swift 6 Strict Concurrency.
public enum MCPValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case integer(Int)
    case double(Double)
    case string(String)
    case array([MCPValue])
    case object([String: MCPValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let val = try? container.decode(Bool.self) {
            self = .bool(val)
        } else if let val = try? container.decode(Int.self) {
            self = .integer(val)
        } else if let val = try? container.decode(Double.self) {
            self = .double(val)
        } else if let val = try? container.decode(String.self) {
            self = .string(val)
        } else if let val = try? container.decode([MCPValue].self) {
            self = .array(val)
        } else if let val = try? container.decode([String: MCPValue].self) {
            self = .object(val)
        } else {
            self = .null
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let val):
            try container.encode(val)
        case .integer(let val):
            try container.encode(val)
        case .double(let val):
            try container.encode(val)
        case .string(let val):
            try container.encode(val)
        case .array(let val):
            try container.encode(val)
        case .object(let val):
            try container.encode(val)
        }
    }
}

public struct MCPRequest: Codable, Sendable {
    public let jsonrpc: String
    public let method: String?
    public let params: [String: MCPValue]?
    public let id: MCPValue?
}

public struct MCPResponse: Codable, Sendable {
    public let jsonrpc: String = "2.0"
    public let id: MCPValue?
    public let result: MCPValue?
    public let error: MCPResponseError?

    public init(id: MCPValue?, result: MCPValue? = nil, error: MCPResponseError? = nil) {
        self.id = id
        self.result = result
        self.error = error
    }
}

public struct MCPResponseError: Codable, Sendable {
    public let code: Int
    public let message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}

/// A local HTTP-based JSON-RPC 2.0 MCP Server for Symaira Terminal.
public final class MCPServer: @unchecked Sendable {
    private let listener: NWListener
    private weak var delegate: (any TerminalMCPDelegate)?
    private let queue = DispatchQueue(label: "com.symaira.mcp-server")
    private let port: UInt16

    public init(port: UInt16 = 8888, delegate: any TerminalMCPDelegate) throws {
        self.port = port
        self.delegate = delegate
        let parameters = NWParameters.tcp
        // Only bind to localhost for security
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        self.listener = try NWListener(using: parameters)
    }

    public func start() {
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                NSLog("symaira: MCP server listening on 127.0.0.1:\(self.port)")
            case .failed(let error):
                NSLog("symaira: MCP server failed to start: \(error)")
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener.start(queue: queue)
    }

    public func stop() {
        listener.cancel()
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        readRequest(connection: connection, accumulatedData: Data())
    }

    private func readRequest(connection: NWConnection, accumulatedData: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else { return }
            if let error {
                NSLog("symaira: MCP connection read error: \(error)")
                connection.cancel()
                return
            }

            var data = accumulatedData
            if let content {
                data.append(content)
            }

            if let headerEndRange = data.range(of: Data("\r\n\r\n".utf8)) {
                let headersData = data.subdata(in: 0..<headerEndRange.lowerBound)
                let bodyStart = headerEndRange.upperBound

                if let headersString = String(data: headersData, encoding: .utf8) {
                    var contentLength = 0
                    for line in headersString.components(separatedBy: "\r\n") where line.lowercased().hasPrefix("content-length:") {
                        let parts = line.components(separatedBy: ":")
                        if parts.count > 1 {
                            contentLength = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
                        }
                    }

                    let bodyData = data.subdata(in: bodyStart..<data.count)
                    if bodyData.count >= contentLength {
                        let requestBody = bodyData.subdata(in: 0..<contentLength)
                        self.processHTTPRequest(connection: connection, headers: headersString, body: requestBody)
                        return
                    }
                }
            }

            if isComplete {
                connection.cancel()
            } else {
                self.readRequest(connection: connection, accumulatedData: data)
            }
        }
    }

    private func processHTTPRequest(connection: NWConnection, headers: String, body: Data) {
        Task {
            let decoder = JSONDecoder()
            guard let request = try? decoder.decode(MCPRequest.self, from: body) else {
                let errResp = MCPResponse(id: .null, error: MCPResponseError(code: -32700, message: "Parse error"))
                sendJSONResponse(connection: connection, response: errResp)
                return
            }

            // Route standard JSON-RPC MCP methods
            guard let method = request.method else {
                let errResp = MCPResponse(id: request.id ?? .null, error: MCPResponseError(code: -32600, message: "Invalid Request"))
                sendJSONResponse(connection: connection, response: errResp)
                return
            }

            switch method {
            case "initialize":
                let serverInfo: [String: MCPValue] = [
                    "name": .string("symaira-terminal"),
                    "version": .string("0.7.0")
                ]
                let capabilities: [String: MCPValue] = [
                    "tools": .object([:])
                ]
                let result: [String: MCPValue] = [
                    "protocolVersion": .string("2024-11-05"),
                    "capabilities": .object(capabilities),
                    "serverInfo": .object(serverInfo)
                ]
                let resp = MCPResponse(id: request.id ?? .null, result: .object(result))
                sendJSONResponse(connection: connection, response: resp)

            case "notifications/initialized":
                sendHTTPResponse(connection: connection, statusCode: 200, statusText: "OK", contentType: "application/json", body: Data())

            case "tools/list":
                let tools: [MCPValue] = [
                    .object([
                        "name": .string("read_scrollback"),
                        "description": .string("Get the last N lines of the active terminal session scrollback buffer."),
                        "inputSchema": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "lines": .object([
                                    "type": .string("integer"),
                                    "description": .string("Number of scrollback lines to return (default 100, max 1000).")
                                ])
                            ])
                        ])
                    ]),
                    .object([
                        "name": .string("open_tab"),
                        "description": .string("Open a new terminal tab and execute the specified command. This requires explicit user confirmation in the terminal UI."),
                        "inputSchema": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "command": .object([
                                    "type": .string("string"),
                                    "description": .string("The shell command to run in the new tab.")
                                ])
                            ]),
                            "required": .array([.string("command")])
                        ])
                    ])
                ]
                let result: [String: MCPValue] = [
                    "tools": .array(tools)
                ]
                let resp = MCPResponse(id: request.id ?? .null, result: .object(result))
                sendJSONResponse(connection: connection, response: resp)

            case "tools/call":
                guard let params = request.params else {
                    let resp = MCPResponse(id: request.id ?? .null, error: MCPResponseError(code: -32602, message: "Invalid params"))
                    sendJSONResponse(connection: connection, response: resp)
                    return
                }
                guard let nameVal = params["name"], case .string(let toolName) = nameVal else {
                    let resp = MCPResponse(id: request.id ?? .null, error: MCPResponseError(code: -32602, message: "Invalid params: name is required"))
                    sendJSONResponse(connection: connection, response: resp)
                    return
                }

                let args = params["arguments"]

                if toolName == "read_scrollback" {
                    var lines = 100
                    if case .object(let argObj) = args, let linesVal = argObj["lines"] {
                        if case .integer(let l) = linesVal {
                            lines = l
                        } else if case .double(let d) = linesVal {
                            lines = Int(d)
                        }
                    }
                    if lines <= 0 { lines = 100 }
                    if lines > 1000 { lines = 1000 }

                    let scrollbackText = await delegate?.getActiveScrollback(lines: lines) ?? ""
                    let contentItem: [String: MCPValue] = [
                        "type": .string("text"),
                        "text": .string(scrollbackText)
                    ]
                    let resultVal: [String: MCPValue] = [
                        "content": .array([.object(contentItem)])
                    ]
                    let resp = MCPResponse(id: request.id ?? .null, result: .object(resultVal))
                    sendJSONResponse(connection: connection, response: resp)

                } else if toolName == "open_tab" {
                    var command = ""
                    if case .object(let argObj) = args, let cmdVal = argObj["command"] {
                        if case .string(let s) = cmdVal {
                            command = s
                        }
                    }
                    if command.isEmpty {
                        let resp = MCPResponse(id: request.id ?? .null, error: MCPResponseError(code: -32602, message: "command is required"))
                        sendJSONResponse(connection: connection, response: resp)
                        return
                    }

                    let allowed = await delegate?.openTab(command: command) ?? false
                    if allowed {
                        let contentItem: [String: MCPValue] = [
                            "type": .string("text"),
                            "text": .string("Successfully opened new tab with command: \(command)")
                        ]
                        let resultVal: [String: MCPValue] = [
                            "content": .array([.object(contentItem)])
                        ]
                        let resp = MCPResponse(id: request.id ?? .null, result: .object(resultVal))
                        sendJSONResponse(connection: connection, response: resp)
                    } else {
                        let contentItem: [String: MCPValue] = [
                            "type": .string("text"),
                            "text": .string("User denied request to open new tab with command: \(command)")
                        ]
                        let resultVal: [String: MCPValue] = [
                            "content": .array([.object(contentItem)]),
                            "isError": .bool(true)
                        ]
                        let resp = MCPResponse(id: request.id ?? .null, result: .object(resultVal))
                        sendJSONResponse(connection: connection, response: resp)
                    }

                } else {
                    let resp = MCPResponse(id: request.id ?? .null, error: MCPResponseError(code: -32601, message: "Tool not found: \(toolName)"))
                    sendJSONResponse(connection: connection, response: resp)
                }

            default:
                let resp = MCPResponse(id: request.id ?? .null, error: MCPResponseError(code: -32601, message: "Method not found: \(method)"))
                sendJSONResponse(connection: connection, response: resp)
            }
        }
    }

    private func sendJSONResponse(connection: NWConnection, response: MCPResponse) {
        let encoder = JSONEncoder()
        guard let responseData = try? encoder.encode(response) else {
            sendHTTPResponse(connection: connection, statusCode: 500, statusText: "Internal Server Error", contentType: "text/plain", body: Data("Error encoding JSON response".utf8))
            return
        }
        sendHTTPResponse(connection: connection, statusCode: 200, statusText: "OK", contentType: "application/json", body: responseData)
    }

    private func sendHTTPResponse(connection: NWConnection, statusCode: Int, statusText: String, contentType: String, body: Data) {
        var responseString = "HTTP/1.1 \(statusCode) \(statusText)\r\n"
        responseString += "Content-Type: \(contentType)\r\n"
        responseString += "Content-Length: \(body.count)\r\n"
        responseString += "Connection: close\r\n"
        responseString += "\r\n"

        guard let headerData = responseString.data(using: .utf8) else {
            connection.cancel()
            return
        }

        var fullResponse = Data()
        fullResponse.append(headerData)
        fullResponse.append(body)

        connection.send(content: fullResponse, completion: .contentProcessed({ error in
            if let error {
                NSLog("symaira: MCP connection send error: \(error)")
            }
            connection.cancel()
        }))
    }
}
