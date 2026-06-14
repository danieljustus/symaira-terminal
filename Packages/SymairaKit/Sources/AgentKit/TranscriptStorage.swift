import Foundation

public struct TranscriptEntry: Codable, Sendable {
    public let id: String
    public let timestamp: Date
    public let sessionId: String
    public let content: [TranscriptMessage]
    public let metadata: TranscriptMetadata

    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        sessionId: String,
        content: [TranscriptMessage],
        metadata: TranscriptMetadata
    ) {
        self.id = id
        self.timestamp = timestamp
        self.sessionId = sessionId
        self.content = content
        self.metadata = metadata
    }
}

public struct TranscriptMessage: Codable, Sendable {
    public let role: MessageRole
    public let content: String
    public let timestamp: Date
    public let toolCalls: [ToolCall]?

    public init(
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        toolCalls: [ToolCall]? = nil
    ) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolCalls = toolCalls
    }
}

public enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
    case tool
}

public struct ToolCall: Codable, Sendable {
    public let name: String
    public let arguments: String
    public let result: String?

    public init(name: String, arguments: String, result: String? = nil) {
        self.name = name
        self.arguments = arguments
        self.result = result
    }
}

public struct TranscriptMetadata: Codable, Sendable {
    public let repositoryURL: String?
    public let branch: String?
    public let workingDirectory: String?
    public let agentType: String?

    public init(
        repositoryURL: String? = nil,
        branch: String? = nil,
        workingDirectory: String? = nil,
        agentType: String? = nil
    ) {
        self.repositoryURL = repositoryURL
        self.branch = branch
        self.workingDirectory = workingDirectory
        self.agentType = agentType
    }
}

public struct TranscriptStorage: @unchecked Sendable {
    public static let shared = TranscriptStorage()

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public var storageDirectory: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SymairaTerminal/transcripts", isDirectory: true)
    }

    public init() {
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
    }

    public func save(_ entry: TranscriptEntry) throws {
        let directory = storageDirectory
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            // Protect the directory so transcript files inherit NSFileProtection.complete.
            // This prevents other processes from reading transcript data when the device is locked.
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: directory.path
            )
        }

        let fileURL = directory.appendingPathComponent("\(entry.id).json")
        let data = try encoder.encode(entry)
        try data.write(to: fileURL, options: .atomic)
    }

    public func load(id: String) -> TranscriptEntry? {
        let fileURL = storageDirectory.appendingPathComponent("\(id).json")
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL)
        else { return nil }

        return try? decoder.decode(TranscriptEntry.self, from: data)
    }

    public func list() -> [TranscriptEntry] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: storageDirectory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { try? decoder.decode(TranscriptEntry.self, from: $0) }
            .sorted { $0.timestamp > $1.timestamp }
    }

    public func delete(id: String) throws {
        let fileURL = storageDirectory.appendingPathComponent("\(id).json")
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }
}
