import Foundation

/// Errors that can occur during tool detection.
public enum StackDetectionError: Error, Sendable {
    case binaryNotFound(String)
    case versionQueryTimeout(String)
    case versionQueryFailed(String, Error)
}

/// Detects installed Symaira CLI tools by searching PATH and querying versions.
public actor StackDetector {
    private let fileManager: FileManager
    private let pathEnvironment: String

    public init(
        fileManager: FileManager = .default,
        pathEnvironment: String? = nil
    ) {
        self.fileManager = fileManager
        self.pathEnvironment = pathEnvironment
            ?? ProcessInfo.processInfo.environment["PATH"]
            ?? "/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin"
    }

    /// Detect all Symaira tools: check PATH, query versions, determine MCP support.
    public func detectAll() async -> [DetectedTool] {
        await withTaskGroup(of: DetectedTool.self) { group in
            for tool in SymairaToolRegistry.all {
                group.addTask { [self] in
                    await self.detect(tool: tool)
                }
            }

            var results: [DetectedTool] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.tool.displayName < $1.tool.displayName }
        }
    }

    /// Detect a single tool: PATH lookup → version query → MCP capability.
    public func detect(tool: SymairaTool) async -> DetectedTool {
        guard let path = findInPATH(tool.binaryName) else {
            return DetectedTool(tool: tool, path: nil, version: nil, mcpSupported: false)
        }

        let version = await queryVersion(binaryPath: path)
        return DetectedTool(
            tool: tool,
            path: path,
            version: version,
            mcpSupported: tool.supportsMCP
        )
    }

    // MARK: - PATH Lookup

    /// Search PATH directories for the binary.
    func findInPATH(_ binaryName: String) -> String? {
        let directories = pathEnvironment.components(separatedBy: ":")
        for dir in directories {
            let fullPath = (dir as NSString).appendingPathComponent(binaryName)
            if fileManager.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }
        return nil
    }

    // MARK: - Version Query

    /// Query the tool's version with a 3-second timeout.
    ///
    /// `nonisolated` and dispatched to a global queue: the blocking
    /// `waitUntilExit()` must not occupy the actor or a cooperative-pool
    /// thread, otherwise the version queries in `detectAll()` serialize and a
    /// single refresh can stall for `timeout × tool count`.
    nonisolated func queryVersion(binaryPath: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.runVersionQuery(binaryPath: binaryPath))
            }
        }
    }

    /// Blocking version query. Must be called off the cooperative thread pool.
    private nonisolated static func runVersionQuery(binaryPath: String) -> String? {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["version"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        // Terminate if the timeout is exceeded (3 seconds).
        let timeout = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
            }
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 3, execute: timeout)

        process.waitUntilExit()
        timeout.cancel()

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
            .first
    }
}
