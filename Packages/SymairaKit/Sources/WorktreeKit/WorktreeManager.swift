import Foundation

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
        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw WorktreeError.gitFailed(
                arguments: arguments,
                exitCode: process.terminationStatus,
                stderr: String(data: errData, encoding: .utf8) ?? ""
            )
        }
        return String(data: outData, encoding: .utf8) ?? ""
    }
}
