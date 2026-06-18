import ControlKit
import Darwin
import Foundation

// MARK: - MCP JSON-RPC 2.0 Wire Types

/// An incoming JSON-RPC 2.0 request as defined by the MCP specification.
struct MCPRequest: Codable, Sendable {
    var jsonrpc: String
    var id: MCPRequestID?
    var method: String
    var params: MCPRequestParams?
}

/// MCP request ID — may be Int or String per JSON-RPC 2.0 spec.
enum MCPRequestID: Codable, Sendable, Equatable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Int.self) { self = .int(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "id must be Int or String")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .int(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        }
    }
}

/// Generic params bag — we only need the "arguments" dictionary for `tools/call`.
struct MCPRequestParams: Codable, Sendable {
    /// Tool name for `tools/call`.
    var name: String?
    /// Tool arguments for `tools/call`.
    var arguments: [String: AnyCodable]?
}

/// Type-erased Codable value for JSON dictionaries.
struct AnyCodable: Codable, Sendable {
    let value: any Sendable

    init(_ value: some Sendable) { self.value = value }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Int.self)    { value = v; return }
        if let v = try? c.decode(Double.self) { value = v; return }
        if let v = try? c.decode(Bool.self)   { value = v; return }
        if let v = try? c.decode(String.self) { value = v; return }
        value = ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let v as Int:    try c.encode(v)
        case let v as Double: try c.encode(v)
        case let v as Bool:   try c.encode(v)
        case let v as String: try c.encode(v)
        default:              try c.encode(String(describing: value))
        }
    }
}

// MARK: - MCP Response Types

struct MCPResponse: Codable, Sendable {
    var jsonrpc: String = "2.0"
    var id: MCPRequestID?
    var result: MCPResult?
    var error: MCPError?
}

struct MCPResult: Codable, Sendable {
    // tools/list
    var tools: [MCPToolDefinition]?
    // tools/call
    var content: [MCPContent]?
    var isError: Bool?
    // initialize
    var protocolVersion: String?
    var capabilities: MCPCapabilities?
    var serverInfo: MCPServerInfo?
}

struct MCPError: Codable, Sendable {
    var code: Int
    var message: String

    static let parseError       = MCPError(code: -32700, message: "Parse error")
    static let methodNotFound   = MCPError(code: -32601, message: "Method not found")
    static let invalidParams    = MCPError(code: -32602, message: "Invalid params")
    static let internalError    = MCPError(code: -32603, message: "Internal error")
}

struct MCPContent: Codable, Sendable {
    var type: String  // "text"
    var text: String
}

struct MCPCapabilities: Codable, Sendable {
    var tools: MCPToolsCapability?
}

struct MCPToolsCapability: Codable, Sendable {
    var listChanged: Bool?
}

struct MCPServerInfo: Codable, Sendable {
    var name: String
    var version: String
}

// MARK: - Tool Definitions

/// JSON Schema for a single tool input property.
struct MCPPropertySchema: Codable, Sendable {
    var type: String
    var description: String
    var `default`: AnyCodable?
}

/// Full JSON Schema for a tool's input_schema.
struct MCPInputSchema: Codable, Sendable {
    var type: String = "object"
    var properties: [String: MCPPropertySchema]?
    var required: [String]?
}

/// A single MCP tool definition returned by `tools/list`.
struct MCPToolDefinition: Codable, Sendable {
    var name: String
    var description: String
    var inputSchema: MCPInputSchema

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "inputSchema"
    }
}
