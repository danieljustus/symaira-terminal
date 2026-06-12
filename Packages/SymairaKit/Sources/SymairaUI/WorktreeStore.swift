import Foundation
import WorktreeKit

@MainActor
public final class WorktreeStore: ObservableObject {
    @Published public var worktrees: [Worktree] = []
    @Published public var error: WorktreeError?

    // nonisolated(unsafe): WorktreeManager uses Process per call (thread-safe in practice)
    // but is not formally Sendable. Captured in detached tasks for background git work.
    nonisolated(unsafe) private let manager: WorktreeManager

    private var dirtyCache: [URL: Bool] = [:]
    private var dirtyTask: Task<Void, Never>?
    private var diffTask: Task<String?, Never>?

    public init(repositoryURL: URL, containerURL: URL? = nil) {
        self.manager = WorktreeManager(repositoryURL: repositoryURL, containerURL: containerURL)
    }

    public func refresh() {
        do {
            worktrees = try manager.list()
            error = nil
            refreshDirtyState(for: worktrees)
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

    // MARK: - Async dirty state

    /// Cancels any in-flight dirty check and spawns a background task that runs
    /// `git status --porcelain` for each worktree off the main actor, then updates
    /// `dirtyCache` on the main actor when complete.
    public func refreshDirtyState(for worktrees: [Worktree]) {
        dirtyTask?.cancel()
        let paths = worktrees.map(\.path)
        dirtyTask = Task.detached { [weak self] in
            var results: [URL: Bool] = [:]
            for path in paths {
                if Task.isCancelled { return }
                results[path] = WorktreeStore.checkDirty(path: path)
            }
            if Task.isCancelled { return }
            await self?.applyDirtyCache(results)
        }
    }

    private func applyDirtyCache(_ results: [URL: Bool]) {
        dirtyCache = results
    }

    /// Returns the cached dirty state for a worktree. Safe to call during view
    /// rendering — never blocks. Returns `false` if the cache has not been
    /// populated yet (call `refreshDirtyState(for:)` first).
    public func isDirtyCached(_ worktree: Worktree) -> Bool {
        dirtyCache[worktree.path] ?? false
    }

    // MARK: - Async diff

    /// Loads a diff asynchronously with automatic cancellation of the previous
    /// request. Ideal for rapid selection changes — only the most recent call
    /// returns a non-nil result; earlier calls return `nil` when cancelled.
    public func loadDiff(_ worktree: Worktree, against baseRef: String = "HEAD") async -> String? {
        diffTask?.cancel()
        let task = Task<String?, Never>.detached { [manager] in
            if Task.isCancelled { return nil }
            return try? manager.diff(worktree, against: baseRef)
        }
        diffTask = task
        return await task.value
    }

    // MARK: - Cleanup

    /// Cancels all in-flight background tasks (dirty checks and diffs).
    public func cancelPendingTasks() {
        dirtyTask?.cancel()
        dirtyTask = nil
        diffTask?.cancel()
        diffTask = nil
    }

    // MARK: - Synchronous (legacy)

    @available(*, deprecated, message: "Use isDirtyCached(_:) for UI; refreshDirtyState(for:) populates the cache off the main actor.")
    public func isDirty(_ worktree: Worktree) -> Bool {
        Self.checkDirty(path: worktree.path)
    }

    @available(*, deprecated, message: "Use loadDiff(_:against:) for async diff loading with cancellation.")
    public func diff(_ worktree: Worktree, against baseRef: String = "HEAD") throws -> String {
        try manager.diff(worktree, against: baseRef)
    }

    // MARK: - Private helpers

    private nonisolated static func checkDirty(path: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["status", "--porcelain"]
        process.currentDirectoryURL = path
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
