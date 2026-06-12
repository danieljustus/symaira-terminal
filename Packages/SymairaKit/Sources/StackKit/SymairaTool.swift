import Foundation

/// Represents a detected Symaira CLI tool and its capabilities.
public struct SymairaTool: Equatable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let binaryName: String
    public let homebrewFormula: String
    public let detectedPath: String?
    public let version: String?
    public let supportsMCP: Bool
    public let mcpArgs: [String]

    public var isInstalled: Bool {
        detectedPath != nil
    }

    public init(
        id: String,
        displayName: String,
        binaryName: String,
        homebrewFormula: String,
        detectedPath: String? = nil,
        version: String? = nil,
        supportsMCP: Bool = true,
        mcpArgs: [String] = ["mcp"]
    ) {
        self.id = id
        self.displayName = displayName
        self.binaryName = binaryName
        self.homebrewFormula = homebrewFormula
        self.detectedPath = detectedPath
        self.version = version
        self.supportsMCP = supportsMCP
        self.mcpArgs = mcpArgs
    }
}

/// Registry of all known Symaira CLI tools with their MCP serve commands.
public enum SymairaToolRegistry {
    public static let all: [SymairaTool] = [
        SymairaTool(
            id: "symvault",
            displayName: "Symaira Vault",
            binaryName: "symvault",
            homebrewFormula: "danieljustus/tap/symvault",
            mcpArgs: ["serve", "--stdio", "--agent", "symaira-terminal"]
        ),
        SymairaTool(
            id: "symmemory",
            displayName: "Symaira Memory",
            binaryName: "symmemory",
            homebrewFormula: "danieljustus/tap/symmemory",
            mcpArgs: ["serve"]
        ),
        SymairaTool(
            id: "symseek",
            displayName: "Symaira Seek",
            binaryName: "symseek",
            homebrewFormula: "danieljustus/tap/symseek",
            mcpArgs: ["serve"]
        ),
        SymairaTool(
            id: "symfetch",
            displayName: "Symaira Fetch",
            binaryName: "symfetch",
            homebrewFormula: "danieljustus/tap/symfetch",
            mcpArgs: ["mcp"]
        ),
    ]
}
