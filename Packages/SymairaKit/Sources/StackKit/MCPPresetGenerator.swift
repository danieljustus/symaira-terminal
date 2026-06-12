import Foundation

/// Generates `symaira-mcp.json` preset files for MCP client configuration.
public struct MCPPresetGenerator {

    /// A single MCP server entry in the preset file.
    public struct MCPServerEntry: Codable, Equatable, Sendable {
        public let command: String
        public let args: [String]

        public init(command: String, args: [String]) {
            self.command = command
            self.args = args
        }
    }

    /// The complete MCP preset file structure.
    public struct MCPPreset: Codable, Equatable, Sendable {
        public var mcpServers: [String: MCPServerEntry]

        public init(mcpServers: [String: MCPServerEntry] = [:]) {
            self.mcpServers = mcpServers
        }
    }

    /// Generate a preset from detected tools.
    /// Only includes tools that are installed and support MCP.
    public static func generate(from detectedTools: [DetectedTool]) -> MCPPreset {
        var servers: [String: MCPServerEntry] = [:]

        for tool in detectedTools where tool.isInstalled && tool.mcpSupported {
            guard let path = tool.path else { continue }
            servers[tool.tool.id] = MCPServerEntry(
                command: path,
                args: tool.tool.mcpArgs
            )
        }

        return MCPPreset(mcpServers: servers)
    }

    /// Encode preset as pretty-printed JSON data.
    public static func encode(_ preset: MCPPreset) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(preset)
    }

    /// Decode preset from JSON data.
    public static func decode(from data: Data) throws -> MCPPreset {
        return try JSONDecoder().decode(MCPPreset.self, from: data)
    }
}
