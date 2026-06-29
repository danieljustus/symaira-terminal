import Foundation

/// Handles saving and loading session state to/from disk.
///
/// Storage location: `~/Library/Application Support/SymairaTerminal/sessions.json`
/// A backup of the previous session is kept at `sessions.json.bak` to survive
/// corrupted writes.
///
/// Supports debounced writes to reduce disk I/O under rapid pane operations.
/// Use `save(_:)` for normal saves (debounced) and `saveImmediately(_:)` for
/// termination saves (no debounce delay).
public final class SessionPersistence: @unchecked Sendable {
    public static let shared = SessionPersistence()

    private let fileManager = FileManager.default
    private let debounceInterval: TimeInterval
    private var pendingSaveTask: Task<Void, Never>?
    private var pendingState: SessionState?
    private let _storageDirectory: URL?

    public var storageDirectory: URL {
        _storageDirectory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SymairaTerminal", isDirectory: true)
    }

    public var sessionFile: URL {
        storageDirectory.appendingPathComponent("sessions.json")
    }

    public var backupFile: URL {
        storageDirectory.appendingPathComponent("sessions.json.bak")
    }

    public init(debounceInterval: TimeInterval = 0.5) {
        self.debounceInterval = debounceInterval
        self._storageDirectory = nil
    }

    /// Internal initializer for testing with custom storage directory.
    init(storageDirectory: URL, debounceInterval: TimeInterval = 0.5) {
        self.debounceInterval = debounceInterval
        self._storageDirectory = storageDirectory
    }

    // MARK: - Save (Debounced)

    /// Saves session state with debouncing. Rapid calls within the debounce
    /// interval will coalesce into a single write.
    public func save(_ state: SessionState) throws {
        pendingSaveTask?.cancel()
        pendingState = state

        pendingSaveTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.debounceInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if let state = self.pendingState {
                try? self.performSave(state)
                self.pendingState = nil
            }
        }
    }

    /// Saves session state immediately, bypassing debounce.
    /// Use this for app termination to ensure state is persisted.
    public func saveImmediately(_ state: SessionState) throws {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        pendingState = nil
        try performSave(state)
    }

    private func performSave(_ state: SessionState) throws {
        let directory = storageDirectory
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: directory.path
            )
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)

        if fileManager.fileExists(atPath: sessionFile.path) {
            if fileManager.fileExists(atPath: backupFile.path) {
                try? fileManager.removeItem(at: backupFile)
            }
            try? fileManager.moveItem(at: sessionFile, to: backupFile)
        }

        try data.write(to: sessionFile, options: .atomic)
    }

    // MARK: - Load

    public func load() -> SessionState? {
        if let state = load(from: sessionFile) {
            return state
        }
        if let state = load(from: backupFile) {
            NSLog("session restore: using backup (primary was corrupted or missing)")
            return state
        }
        return nil
    }

    private func load(from url: URL) -> SessionState? {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url)
        else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SessionState.self, from: data)
    }

    // MARK: - Delete

    public func deleteSession() {
        try? fileManager.removeItem(at: sessionFile)
        try? fileManager.removeItem(at: backupFile)
    }
}
