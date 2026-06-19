import Foundation

/// Handles saving and loading session state to/from disk.
///
/// Storage location: `~/Library/Application Support/SymairaTerminal/sessions.json`
/// A backup of the previous session is kept at `sessions.json.bak` to survive
/// corrupted writes.
public struct SessionPersistence: @unchecked Sendable {
    public static let shared = SessionPersistence()

    private let fileManager = FileManager.default

    public var storageDirectory: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SymairaTerminal", isDirectory: true)
    }

    public var sessionFile: URL {
        storageDirectory.appendingPathComponent("sessions.json")
    }

    public var backupFile: URL {
        storageDirectory.appendingPathComponent("sessions.json.bak")
    }

    public init() {}

    // MARK: - Save

    public func save(_ state: SessionState) throws {
        let directory = storageDirectory
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            // Protect session files so they are inaccessible when the device is locked.
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: directory.path
            )
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)

        // Keep backup of previous save.
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
        // Try primary file first.
        if let state = load(from: sessionFile) {
            return state
        }
        // Fall back to backup.
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
