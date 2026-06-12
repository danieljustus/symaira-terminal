import Foundation

/// Result of detecting a single Symaira tool.
public struct DetectedTool: Equatable, Sendable, Identifiable {
    public let tool: SymairaTool
    public let path: String?
    public let version: String?
    public let mcpSupported: Bool

    public var id: String { tool.id }
    public var isInstalled: Bool { path != nil }
    public var displayName: String { tool.displayName }
    public var binaryName: String { tool.binaryName }
    public var homebrewFormula: String { tool.homebrewFormula }

    public init(
        tool: SymairaTool,
        path: String?,
        version: String?,
        mcpSupported: Bool
    ) {
        self.tool = tool
        self.path = path
        self.version = version
        self.mcpSupported = mcpSupported
    }
}
