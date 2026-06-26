import Darwin
import Foundation
import TerminalCore

public struct Worktree: Equatable, Hashable, Sendable {
    public let taskID: String
    public let path: URL
    public let branch: String
}

public enum WorktreeError: Error, Equatable {
    case gitFailed(arguments: [String], exitCode: Int32, stderr: String)
    case notARepository(URL)
    case invalidTaskID(TaskIDError)
}

public struct WorktreeManager: Sendable {
    public static let branchPrefix = "symaira/task-"

    public let repositoryURL: URL
    public let containerURL: URL
    private let validator: TaskIDValidator

    public init(repositoryURL: URL, containerURL: URL? = nil, validator: TaskIDValidator = TaskIDValidator()) {
        self.repositoryURL = repositoryURL
        self.containerURL = containerURL
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("SymairaTerminal/worktrees", isDirectory: true)
        self.validator = validator
    }

    @discardableResult
    public func create(taskID: String, baseRef: String = "HEAD") throws -> Worktree {
        let safePath: URL
        do {
            safePath = try validator.sanitizedPath(for: taskID, under: containerURL)
        } catch let error as TaskIDError {
            throw WorktreeError.invalidTaskID(error)
        }

        let branch = Self.branchPrefix + taskID
        try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        try git(["worktree", "add", "-b", branch, safePath.path, baseRef])
        return Worktree(taskID: taskID, path: safePath, branch: branch)
    }

    public func remove(_ worktree: Worktree, deleteBranch: Bool = true, force: Bool = false) throws {
        var args = ["worktree", "remove", worktree.path.path]
        if force { args.append("--force") }
        try git(args)
        if deleteBranch {
            try git(["branch", force ? "-D" : "-d", worktree.branch])
        }
    }

    /// Lists worktrees previously created by this manager (recognized by the
    /// branch prefix), parsed from `git worktree list --porcelain`.
    public func list() throws -> [Worktree] {
        let output = try git(["worktree", "list", "--porcelain"])
        var result: [Worktree] = []
        var currentPath: URL?
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("worktree ") {
                currentPath = URL(fileURLWithPath: String(line.dropFirst("worktree ".count)))
            } else if line.hasPrefix("branch refs/heads/"), let path = currentPath {
                let branch = String(line.dropFirst("branch refs/heads/".count))
                if branch.hasPrefix(Self.branchPrefix) {
                    let taskID = String(branch.dropFirst(Self.branchPrefix.count))
                    result.append(Worktree(taskID: taskID, path: path, branch: branch))
                }
            }
        }
        return result
    }

    /// Diff of the worktree against its fork point — input for the review panel.
    public func diff(_ worktree: Worktree, against baseRef: String = "HEAD") throws -> String {
        try git(["diff", baseRef], cwd: worktree.path)
    }

    // MARK: - git plumbing

    @discardableResult
    func git(_ arguments: [String], cwd: URL? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = cwd ?? repositoryURL
        let (outData, errData, status) = try Self.run(process)
        guard status == 0 else {
            throw WorktreeError.gitFailed(
                arguments: arguments,
                exitCode: status,
                stderr: String(data: errData, encoding: .utf8) ?? ""
            )
        }
        return String(data: outData, encoding: .utf8) ?? ""
    }

    /// Runs a process, draining stdout and stderr concurrently. Delegates to
    /// `ProcessRunner.run` which owns the single canonical drain implementation.
    static func run(_ process: Process) throws -> (stdout: Data, stderr: Data, status: Int32) {
        let r = try ProcessRunner.run(process)
        return (r.stdout, r.stderr, r.exitCode)
    }

    // MARK: - Handoff Pipeline

    public func createHandoffPackage(from worktree: Worktree, against baseRef: String = "HEAD") throws -> HandoffPackage {
        let rawDiff = try diff(worktree, against: baseRef)

        let data = rawDiff.data(using: .utf8) ?? Data()
        guard let compressed = try? (data as NSData).compressed(using: .zlib) as Data else {
            throw NSError(domain: "WorktreeManager", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to compress diff"])
        }
        let base64Diff = compressed.base64EncodedString()

        // Generate summary: git diff --stat
        let statSummary = try git(["diff", "--stat", baseRef], cwd: worktree.path)

        let riskNotes = checkRisks(in: rawDiff)

        return HandoffPackage(
            sourceTaskID: worktree.taskID,
            gitDiffCompressedBase64: base64Diff,
            summary: statSummary,
            riskNotes: riskNotes
        )
    }

    public func applyHandoffPackage(_ package: HandoffPackage, to worktree: Worktree) throws {
        guard let compressedData = Data(base64Encoded: package.gitDiffCompressedBase64) else {
            throw NSError(domain: "WorktreeManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid base64 compressed diff"])
        }

        guard let decompressedNSData = try? (compressedData as NSData).decompressed(using: .zlib),
              let decompressedString = String(data: decompressedNSData as Data, encoding: .utf8) else {
            throw NSError(domain: "WorktreeManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "Decompression failed"])
        }

        let tempFileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".diff")
        try decompressedString.write(to: tempFileURL, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: tempFileURL)
        }

        try git(["apply", tempFileURL.path], cwd: worktree.path)
    }

    private func checkRisks(in diff: String) -> String {
        let redactor = SecretRedactor()
        let result = redactor.redact(diff)
        if result.redactionCount > 0 {
            return "WARNING: \(result.redactionCount) possible secret(s) detected in diff."
        }
        return "No high-risk secrets detected in the diff."
    }
}

// MARK: - HandoffPackage

public struct HandoffPackage: Codable, Sendable {
    public let sourceTaskID: String
    public let gitDiffCompressedBase64: String
    public let summary: String
    public let riskNotes: String

    public init(sourceTaskID: String, gitDiffCompressedBase64: String, summary: String, riskNotes: String) {
        self.sourceTaskID = sourceTaskID
        self.gitDiffCompressedBase64 = gitDiffCompressedBase64
        self.summary = summary
        self.riskNotes = riskNotes
    }
}
