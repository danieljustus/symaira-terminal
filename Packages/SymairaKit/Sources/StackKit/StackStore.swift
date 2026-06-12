import Foundation
import SwiftUI

/// Observable store that manages Symaira stack detection state for the UI.
@MainActor
public final class StackStore: ObservableObject {
    @Published public var detectedTools: [DetectedTool] = []
    @Published public var isScanning = false
    @Published public var lastScanDate: Date?
    @Published public var lastExportDate: Date?
    @Published public var lastExportPath: String?
    @Published public var installStatus: [String: InstallStatus] = [:]
    @Published public var error: String?

    private let detector: StackDetector
    private let installer: MCPClientInstaller

    public init(
        detector: StackDetector = StackDetector(),
        installer: MCPClientInstaller = MCPClientInstaller()
    ) {
        self.detector = detector
        self.installer = installer
    }

    public var installedCount: Int {
        detectedTools.filter(\.isInstalled).count
    }

    public var totalCount: Int {
        SymairaToolRegistry.all.count
    }

    public var preset: MCPPresetGenerator.MCPPreset {
        MCPPresetGenerator.generate(from: detectedTools)
    }

    // MARK: - Actions

    /// Scan PATH and query versions for all known Symaira tools.
    public func scan() async {
        isScanning = true
        error = nil
        defer { isScanning = false }

        detectedTools = await detector.detectAll()
        lastScanDate = Date()
    }

    /// Export the MCP preset to a file URL.
    public func exportPreset(to url: URL) throws {
        let data = try MCPPresetGenerator.encode(preset)
        try data.write(to: url, options: .atomic)
        lastExportDate = Date()
        lastExportPath = url.path
    }

    /// Install preset into a client with backup and merge.
    public func install(to client: MCPClient) throws {
        error = nil
        do {
            let backupPath = try installer.installWithBackup(preset: preset, to: client)
            installStatus[client.rawValue] = .success(backupPath: backupPath)
        } catch {
            installStatus[client.rawValue] = .failure(error.localizedDescription)
            self.error = error.localizedDescription
        }
    }

    /// Generate Claude Code CLI commands.
    public var claudeCodeCommands: [String] {
        MCPClientInstaller.claudeCodeCommands(from: detectedTools)
    }
}

/// Status of a client installation attempt.
public enum InstallStatus: Equatable, Sendable {
    case success(backupPath: String?)
    case failure(String)
}
