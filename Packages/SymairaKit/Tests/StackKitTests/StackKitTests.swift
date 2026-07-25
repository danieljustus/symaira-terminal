import Testing
import Foundation
@testable import StackKit

@Suite struct SymairaToolRegistryTests {
    @Test func registryComesFromSharedToolKit() {
        let tools = SymairaToolRegistry.all
        // The shared registry covers the whole ecosystem (14 tools as of
        // appkit 0.1.0) — the ghost entry symcanvas is gone for good.
        #expect(tools.count >= 14)
        #expect(tools.map(\.id).contains("symvault"))
        #expect(tools.map(\.id).contains("symmemory"))
        #expect(tools.map(\.id).contains("symseek"))
        #expect(tools.map(\.id).contains("symfetch"))
        #expect(tools.map(\.id).contains("symscope"))
        #expect(!tools.map(\.id).contains("symcanvas"))
    }

    @Test func mcpToolsDeclareArgs() {
        for tool in SymairaToolRegistry.all where tool.supportsMCP {
            #expect(!tool.mcpArgs.isEmpty, "Expected \(tool.id) to declare MCP args")
        }
    }

    @Test func correctMCPArgs() {
        // Terminal-specific extras are layered on via terminalMCPArgs;
        // the shared registry stays agent-neutral.
        let vault = SymairaToolRegistry.all.first { $0.id == "symvault" }
        #expect(vault?.mcpArgs == ["serve", "--stdio"])
        #expect(vault?.terminalMCPArgs == ["serve", "--stdio", "--agent", "symaira-terminal"])

        let memory = SymairaToolRegistry.all.first { $0.id == "symmemory" }
        #expect(memory?.mcpArgs == ["serve"])
        #expect(memory?.terminalMCPArgs == ["serve"])

        let seek = SymairaToolRegistry.all.first { $0.id == "symseek" }
        #expect(seek?.mcpArgs == ["serve"])

        let fetch = SymairaToolRegistry.all.first { $0.id == "symfetch" }
        #expect(fetch?.mcpArgs == ["mcp"])
    }
}

@Suite struct MCPPresetGeneratorTests {
    @Test func generatesPresetFromDetectedTools() {
        let tools = [
            DetectedTool(
                tool: SymairaToolRegistry.all[0],
                path: "/opt/homebrew/bin/symvault",
                version: "v0.4.0",
                mcpSupported: true
            ),
            DetectedTool(
                tool: SymairaToolRegistry.all[1],
                path: nil,
                version: nil,
                mcpSupported: true
            )
        ]

        let preset = MCPPresetGenerator.generate(from: tools)
        #expect(preset.mcpServers.count == 1)
        #expect(preset.mcpServers["symvault"]?.command == "/opt/homebrew/bin/symvault")
    }

    @Test func encodesAndDecodesCorrectly() throws {
        let preset = MCPPresetGenerator.MCPPreset(mcpServers: [
            "symvault": MCPPresetGenerator.MCPServerEntry(
                command: "/opt/homebrew/bin/symvault",
                args: ["serve", "--stdio"]
            )
        ])

        let data = try MCPPresetGenerator.encode(preset)
        let decoded = try MCPPresetGenerator.decode(from: data)

        #expect(decoded.mcpServers.count == 1)
        #expect(decoded.mcpServers["symvault"]?.command == "/opt/homebrew/bin/symvault")
        #expect(decoded.mcpServers["symvault"]?.args == ["serve", "--stdio"])
    }

    @Test func encodesToValidJSON() throws {
        let preset = MCPPresetGenerator.MCPPreset(mcpServers: [
            "symvault": MCPPresetGenerator.MCPServerEntry(
                command: "/usr/bin/symvault",
                args: ["mcp"]
            )
        ])

        let data = try MCPPresetGenerator.encode(preset)
        let jsonString = String(data: data, encoding: .utf8)!

        #expect(jsonString.contains("\"mcpServers\""))
        #expect(jsonString.contains("\"command\""))
        #expect(jsonString.contains("/usr/bin/symvault"))
    }
}

@Suite struct MCPClientInstallerTests {
    let installer = MCPClientInstaller(fileManager: .default)

    @Test func claudeCodeCommandsGenerated() {
        let tools = [
            DetectedTool(
                tool: SymairaToolRegistry.all[0],
                path: "/opt/homebrew/bin/symvault",
                version: "v0.4.0",
                mcpSupported: true
            )
        ]

        let commands = MCPClientInstaller.claudeCodeCommands(from: tools)
        #expect(commands.count == 1)
        #expect(commands[0].contains("claude mcp add"))
        #expect(commands[0].contains("/opt/homebrew/bin/symvault"))
    }

    @Test func mergePreservesExistingServers() {
        let existing = MCPPresetGenerator.MCPPreset(mcpServers: [
            "custom-server": MCPPresetGenerator.MCPServerEntry(
                command: "/usr/bin/custom",
                args: ["serve"]
            )
        ])

        let newPreset = MCPPresetGenerator.MCPPreset(mcpServers: [
            "symvault": MCPPresetGenerator.MCPServerEntry(
                command: "/opt/homebrew/bin/symvault",
                args: ["mcp"]
            )
        ])

        let merged = installer.merge(existing: existing, newPreset: newPreset)
        #expect(merged.mcpServers.count == 2)
        #expect(merged.mcpServers["custom-server"]?.command == "/usr/bin/custom")
        #expect(merged.mcpServers["symvault"]?.command == "/opt/homebrew/bin/symvault")
    }

    @Test func mergeOverwritesExistingKeys() {
        let existing = MCPPresetGenerator.MCPPreset(mcpServers: [
            "symvault": MCPPresetGenerator.MCPServerEntry(
                command: "/old/path/symvault",
                args: ["old"]
            )
        ])

        let newPreset = MCPPresetGenerator.MCPPreset(mcpServers: [
            "symvault": MCPPresetGenerator.MCPServerEntry(
                command: "/new/path/symvault",
                args: ["new"]
            )
        ])

        let merged = installer.merge(existing: existing, newPreset: newPreset)
        #expect(merged.mcpServers.count == 1)
        #expect(merged.mcpServers["symvault"]?.command == "/new/path/symvault")
    }
}

@Suite struct StackDetectorTests {
    /// A GUI launch inherits launchd's bare PATH — present, but without any of
    /// the prefixes the tools actually install into.
    @Test func defaultSearchPathAddsStandardPrefixesToABarePATH() {
        let path = StackDetector.defaultSearchPath(inherited: "/usr/bin:/bin:/usr/sbin:/sbin")
        let directories = path.components(separatedBy: ":")

        #expect(directories.contains("/opt/homebrew/bin"))
        #expect(directories.contains("/usr/local/bin"))
        // The inherited entries are kept, and kept first.
        #expect(directories.prefix(4) == ["/usr/bin", "/bin", "/usr/sbin", "/sbin"])
    }

    @Test func defaultSearchPathDoesNotDuplicateExistingPrefixes() {
        let path = StackDetector.defaultSearchPath(inherited: "/opt/homebrew/bin:/usr/bin")
        let directories = path.components(separatedBy: ":")

        #expect(directories.filter { $0 == "/opt/homebrew/bin" }.count == 1)
        #expect(directories.first == "/opt/homebrew/bin")
    }

    @Test func defaultSearchPathStillWorksWithoutAnInheritedPATH() {
        let directories = StackDetector.defaultSearchPath(inherited: nil).components(separatedBy: ":")

        #expect(directories.contains("/opt/homebrew/bin"))
        #expect(!directories.contains(""))
    }

    @Test func findInPATHReturnsNilForMissingBinary() async {
        let detector = StackDetector(
            fileManager: .default,
            pathEnvironment: "/nonexistent/path"
        )
        let result = await detector.detect(
            tool: SymairaTool(
                id: "test",
                displayName: "Test",
                binaryName: "nonexistent-binary-12345",
                homebrewFormula: "test/tap/test"
            )
        )
        #expect(result.path == nil)
        #expect(!result.isInstalled)
    }

    @Test func findInPATHFindsExistingBinary() async {
        // /bin/ls exists on macOS
        let detector = StackDetector(
            fileManager: .default,
            pathEnvironment: "/bin"
        )
        let result = await detector.detect(
            tool: SymairaTool(
                id: "ls",
                displayName: "ls",
                binaryName: "ls",
                homebrewFormula: "test/tap/ls",
                supportsMCP: false
            )
        )
        #expect(result.path == "/bin/ls")
        #expect(result.isInstalled)
    }
}

@Suite struct DetectedToolTests {
    @Test func detectedToolEquality() {
        let tool1 = DetectedTool(
            tool: SymairaToolRegistry.all[0],
            path: "/opt/homebrew/bin/symvault",
            version: "v0.4.0",
            mcpSupported: true
        )
        let tool2 = DetectedTool(
            tool: SymairaToolRegistry.all[0],
            path: "/opt/homebrew/bin/symvault",
            version: "v0.4.0",
            mcpSupported: true
        )
        #expect(tool1 == tool2)
    }

    @Test func detectedToolIdMatchesToolId() {
        let tool = DetectedTool(
            tool: SymairaToolRegistry.all[0],
            path: nil,
            version: nil,
            mcpSupported: true
        )
        #expect(tool.id == SymairaToolRegistry.all[0].id)
    }
}
