import Foundation

/// Reads Claude Code usage from its local JSONL transcript files.
///
/// Claude Code writes per-session JSONL files under:
///   ~/.claude/projects/<hashed-path>/<session-id>.jsonl
///
/// Each line is a JSON object. Lines with `type == "assistant"` carry a
/// `message.usage` object with `input_tokens`, `output_tokens`,
/// `cache_creation_input_tokens`, and `cache_read_input_tokens`.
public struct ClaudeCodeReader: UsageReader, Sendable {
    public let provider: UsageProvider = UsageProviders.claudeCode

    private let baseDirectory: URL
    nonisolated(unsafe) private let fileManager: FileManager

    public init(
        baseDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.baseDirectory = baseDirectory
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
        self.fileManager = fileManager
    }

    public func read(since date: Date) async throws -> [UsageSample] {
        let jsonlFiles = findJSONLFiles()
        guard !jsonlFiles.isEmpty else { return [] }

        var samples: [UsageSample] = []
        for fileURL in jsonlFiles {
            let fileSamples = parseFile(fileURL, since: date)
            samples.append(contentsOf: fileSamples)
        }
        return samples
    }

    // MARK: - Private

    private func findJSONLFiles() -> [URL] {
        guard fileManager.fileExists(atPath: baseDirectory.path) else { return [] }
        var result: [URL] = []
        let enumerator = fileManager.enumerator(
            at: baseDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "jsonl" {
                result.append(url)
            }
        }
        return result
    }

    private func parseFile(_ fileURL: URL, since date: Date) -> [UsageSample] {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else { return [] }

        let projectName = fileURL.deletingLastPathComponent().lastPathComponent

        var samples: [UsageSample] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let entry = parseAssistantEntry(String(line), projectName: projectName, filePath: fileURL.path) else {
                continue
            }
            if entry.timestamp >= date {
                samples.append(entry)
            }
        }
        return samples
    }

    private func parseAssistantEntry(_ line: String, projectName: String, filePath: String) -> UsageSample? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        guard let type = obj["type"] as? String, type == "assistant" else { return nil }
        guard let message = obj["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any] else { return nil }

        let inputTokens   = usage["input_tokens"] as? Int ?? 0
        let outputTokens  = usage["output_tokens"] as? Int ?? 0
        let cacheCreate   = usage["cache_creation_input_tokens"] as? Int ?? 0
        let cacheRead     = usage["cache_read_input_tokens"] as? Int ?? 0

        // Skip zero-token entries (tool-call stubs, etc.)
        guard inputTokens + outputTokens + cacheCreate + cacheRead > 0 else { return nil }

        let modelID = (message["model"] as? String) ?? (obj["model"] as? String) ?? "claude-unknown"

        // Derive timestamp from `timestamp` field (ISO8601) or fall back to now.
        let timestamp: Date
        if let tsString = obj["timestamp"] as? String {
            timestamp = ISO8601DateFormatter().date(from: tsString) ?? Date()
        } else {
            return nil  // no timestamp → can't determine if in range, skip
        }

        // Use the message uuid as the stable dedup key.
        let messageID = (obj["uuid"] as? String)
            ?? (message["id"] as? String)
            ?? UUID().uuidString

        return UsageSample(
            id: messageID,
            provider: provider,
            modelID: modelID,
            timestamp: timestamp,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheCreationTokens: cacheCreate,
            cacheReadTokens: cacheRead,
            sourcePath: filePath,
            project: projectName
        )
    }
}
