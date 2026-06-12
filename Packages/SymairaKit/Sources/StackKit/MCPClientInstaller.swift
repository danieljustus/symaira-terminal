import Foundation

/// Errors that can occur during client installation.
public enum ClientInstallError: Error, Sendable {
    case fileNotFound(String)
    case backupFailed(String, Error)
    case writeFailed(String, Error)
    case mergeFailed(String, Error)
}

/// Known MCP client configurations and their file paths.
public enum MCPClient: String, CaseIterable, Sendable, Identifiable {
    case claudeDesktop = "Claude Desktop"
    case cursor = "Cursor"

    public var id: String { rawValue }

    /// Path to the client's MCP configuration file.
    public var configPath: String {
        switch self {
        case .claudeDesktop:
            return NSHomeDirectory()
                + "/Library/Application Support/Claude/claude_desktop_config.json"
        case .cursor:
            return NSHomeDirectory() + "/.cursor/mcp.json"
        }
    }

    /// Human-readable name for display.
    public var displayName: String { rawValue }
}

/// Handles installing MCP presets into known client configurations with backup and merge.
public struct MCPClientInstaller {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - Public API

    /// Get the existing config for a client, or nil if none exists.
    public func existingConfig(for client: MCPClient) throws -> MCPPresetGenerator.MCPPreset? {
        let path = client.configPath
        guard fileManager.fileExists(atPath: path) else {
            return nil
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try MCPPresetGenerator.decode(from: data)
    }

    /// Create a backup of the client's config file.
    /// Returns the backup path, or nil if no file existed to back up.
    @discardableResult
    public func backup(client: MCPClient) throws -> String? {
        let path = client.configPath
        guard fileManager.fileExists(atPath: path) else {
            return nil
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let backupPath = path + ".backup.\(timestamp)"

        do {
            try fileManager.copyItem(atPath: path, toPath: backupPath)
            return backupPath
        } catch {
            throw ClientInstallError.backupFailed(path, error)
        }
    }

    /// Merge new preset into existing config (preserves other MCP servers).
    public func merge(
        existing: MCPPresetGenerator.MCPPreset?,
        newPreset: MCPPresetGenerator.MCPPreset
    ) -> MCPPresetGenerator.MCPPreset {
        guard let existing else { return newPreset }

        var merged = existing
        for (name, entry) in newPreset.mcpServers {
            merged.mcpServers[name] = entry
        }
        return merged
    }

    /// Write the preset to a client's config file.
    public func install(
        preset: MCPPresetGenerator.MCPPreset,
        to client: MCPClient
    ) throws {
        let path = client.configPath
        let data: Data
        do {
            data = try MCPPresetGenerator.encode(preset)
        } catch {
            throw ClientInstallError.writeFailed(path, error)
        }

        // Ensure parent directory exists
        let directory = (path as NSString).deletingLastPathComponent
        if !fileManager.fileExists(atPath: directory) {
            do {
                try fileManager.createDirectory(
                    atPath: directory,
                    withIntermediateDirectories: true
                )
            } catch {
                throw ClientInstallError.writeFailed(path, error)
            }
        }

        do {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            throw ClientInstallError.writeFailed(path, error)
        }
    }

    /// Full install flow: backup → merge → write.
    public func installWithBackup(
        preset: MCPPresetGenerator.MCPPreset,
        to client: MCPClient
    ) throws -> String? {
        let backupPath = try backup(client: client)
        let existing = try existingConfig(for: client)
        let merged = merge(existing: existing, newPreset: preset)
        try install(preset: merged, to: client)
        return backupPath
    }

    // MARK: - Claude Code (CLI hint, not file-based)

    /// Generate the `claude mcp add` commands for Claude Code CLI.
    public static func claudeCodeCommands(from detectedTools: [DetectedTool]) -> [String] {
        detectedTools.filter { $0.isInstalled && $0.mcpSupported }.compactMap { tool in
            guard let path = tool.path else { return nil }
            let args = tool.tool.mcpArgs.joined(separator: " ")
            return "claude mcp add \(tool.tool.id) -- \(path) \(args)"
        }
    }
}
