import Foundation
import WorktreeKit

@MainActor
public final class WorktreeStore: ObservableObject {
    @Published public var worktrees: [Worktree] = []
    @Published public var error: WorktreeError?

    private let manager: WorktreeManager

    public init(repositoryURL: URL, containerURL: URL? = nil) {
        self.manager = WorktreeManager(repositoryURL: repositoryURL, containerURL: containerURL)
    }

    public func refresh() {
        do {
            worktrees = try manager.list()
            error = nil
        } catch let err as WorktreeError {
            error = err
        } catch {
            // WorktreeManager only throws WorktreeError
        }
    }

    @discardableResult
    public func create(taskID: String, baseRef: String = "HEAD") throws -> Worktree {
        let worktree = try manager.create(taskID: taskID, baseRef: baseRef)
        refresh()
        return worktree
    }

    public func remove(_ worktree: Worktree, deleteBranch: Bool = true, force: Bool = false) throws {
        try manager.remove(worktree, deleteBranch: deleteBranch, force: force)
        refresh()
    }

    public func diff(_ worktree: Worktree, against baseRef: String = "HEAD") throws -> String {
        try manager.diff(worktree, against: baseRef)
    }

    public func isDirty(_ worktree: Worktree) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["status", "--porcelain"]
        process.currentDirectoryURL = worktree.path
        let stdout = Pipe()
        process.standardOutput = stdout
        do {
            try process.run()
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return !data.isEmpty
        } catch {
            return false
        }
    }

    public func age(_ worktree: Worktree) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: worktree.path.path),
              let created = attrs[.creationDate] as? Date else {
            return "unknown"
        }
        let interval = Date().timeIntervalSince(created)
        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}
