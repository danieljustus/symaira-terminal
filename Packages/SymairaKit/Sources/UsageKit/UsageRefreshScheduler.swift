import Foundation

/// Configuration for how often the `UsageStore` refreshes usage data.
public struct RefreshConfig: Equatable, Sendable {
    /// Interval between local-file reads when the app is in the foreground.
    public let foregroundInterval: TimeInterval
    /// Interval when the app is backgrounded or idle (reduced to save CPU).
    public let backgroundInterval: TimeInterval
    /// Interval between quota API calls (throttled independently from local reads).
    public let quotaInterval: TimeInterval

    public static let `default` = RefreshConfig(
        foregroundInterval: 30,
        backgroundInterval: 300,
        quotaInterval: 300
    )

    public init(
        foregroundInterval: TimeInterval = 30,
        backgroundInterval: TimeInterval = 300,
        quotaInterval: TimeInterval = 300
    ) {
        self.foregroundInterval = foregroundInterval
        self.backgroundInterval = backgroundInterval
        self.quotaInterval = quotaInterval
    }
}

/// Tracks the last-parse byte offset for a source file so only new bytes
/// are read on subsequent refreshes (incremental tailing).
public actor IncrementalReadCache {
    private var offsets: [String: Int64] = [:]
    private var mtimes: [String: Date]  = [:]

    public init() {}

    /// Returns the offset from which to start reading the file at `path`,
    /// or 0 if the file has never been read or was modified since the last read.
    public func readOffset(for path: String, currentMtime: Date) -> Int64 {
        guard let cached = mtimes[path], cached == currentMtime else {
            offsets[path] = nil
            mtimes[path] = currentMtime
            return 0
        }
        return offsets[path] ?? 0
    }

    /// Record that we successfully read up to `offset` in the file at `path`.
    public func setOffset(_ offset: Int64, path: String, mtime: Date) {
        offsets[path] = offset
        mtimes[path] = mtime
    }

    /// Invalidate the cache for `path` (e.g. on explicit user refresh).
    public func invalidate(path: String) {
        offsets.removeValue(forKey: path)
        mtimes.removeValue(forKey: path)
    }

    /// Invalidate all cached offsets.
    public func invalidateAll() {
        offsets.removeAll()
        mtimes.removeAll()
    }

    // MARK: - Synchronous wrappers for nonisolated reader contexts

    nonisolated public func readOffsetSync(for path: String, currentMtime: Date) -> Int64 {
        getOffsetSync(path: path, currentMtime: currentMtime)
    }

    nonisolated public func setOffsetSync(_ offset: Int64, path: String, mtime: Date) {
        updateOffsetSync(offset, path: path, mtime: mtime)
    }

    private nonisolated func getOffsetSync(path: String, currentMtime: Date) -> Int64 {
        var result: Int64 = 0
        let semaphore = DispatchSemaphore(value: 0)
        Task { @Sendable [self] in
            result = await self.readOffset(for: path, currentMtime: currentMtime)
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    private nonisolated func updateOffsetSync(_ offset: Int64, path: String, mtime: Date) {
        let semaphore = DispatchSemaphore(value: 0)
        Task { @Sendable [self] in
            await self.setOffset(offset, path: path, mtime: mtime)
            semaphore.signal()
        }
        semaphore.wait()
    }
}

/// Drives periodic refresh of the `UsageStore` with App Nap awareness.
///
/// This class is intentionally not coupled to specific OS notification APIs
/// so it can be unit-tested. The App target hooks up `NSWorkspace` or
/// `NSApplicationDelegate` notifications to call `setForeground(true/false)`.
@MainActor
public final class UsageRefreshScheduler {
    public var config: RefreshConfig
    private var isForeground: Bool = true
    private var refreshTask: Task<Void, Never>?
    private var lastQuotaRefresh: Date = .distantPast
    private let onRefresh: @MainActor @Sendable () async -> Void

    public init(
        config: RefreshConfig = .default,
        onRefresh: @escaping @MainActor @Sendable () async -> Void
    ) {
        self.config = config
        self.onRefresh = onRefresh
    }

    /// Start the periodic refresh loop.
    public func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                await self.onRefresh()
                let interval = await self.currentInterval
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    /// Stop the loop (call on deinit or when usage view is dismissed).
    public func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Signal foreground / background state change.
    public func setForeground(_ value: Bool) {
        isForeground = value
        // If we came back to foreground, reschedule immediately.
        if value { triggerImmediateRefresh() }
    }

    /// Trigger an immediate out-of-band refresh (e.g. user taps the refresh button).
    public func triggerImmediateRefresh() {
        Task { await onRefresh() }
    }

    /// Returns `true` when enough time has elapsed since the last quota
    /// fetch for `quotaInterval` to have passed.
    public func isQuotaRefreshDue() -> Bool {
        Date().timeIntervalSince(lastQuotaRefresh) >= config.quotaInterval
    }

    /// Record that a quota fetch just ran (call after `quotaRegistry.fetchAll()`).
    public func recordQuotaRefresh() {
        lastQuotaRefresh = Date()
    }

    private var currentInterval: TimeInterval {
        isForeground ? config.foregroundInterval : config.backgroundInterval
    }
}
