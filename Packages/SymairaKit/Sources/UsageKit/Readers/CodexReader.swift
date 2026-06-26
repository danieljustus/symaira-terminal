import Foundation

/// Reads OpenAI Codex CLI usage from its local JSONL history files.
///
/// Codex CLI writes session transcripts under:
///   ~/.codex/history/<session-id>.jsonl  (or similar)
///
/// Each line is a JSON object. Lines where `role == "assistant"` may carry
/// a `usage` object with `prompt_tokens`, `completion_tokens` and optionally
/// `total_tokens`.
///
/// Note: Codex's log format is not publicly documented. This reader is designed
/// to be resilient — it skips unknown fields and tolerates format drift.
public struct CodexReader: UsageReader, Sendable {
    public let provider: UsageProvider = UsageProviders.codex

    private let historyDirectory: URL
    nonisolated(unsafe) private let fileManager: FileManager

    public init(
        historyDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.historyDirectory = historyDirectory
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/history")
        self.fileManager = fileManager
    }

    public func read(since date: Date) async throws -> [UsageSample] {
        guard fileManager.fileExists(atPath: historyDirectory.path) else { return [] }
        var samples: [UsageSample] = []
        let enumerator = fileManager.enumerator(
            at: historyDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "jsonl" {
                samples.append(contentsOf: parseFile(url, since: date, cache: nil))
            }
        }
        return samples
    }

    public func read(since date: Date, cache: IncrementalReadCache?) async throws -> [UsageSample] {
        guard fileManager.fileExists(atPath: historyDirectory.path) else { return [] }
        var samples: [UsageSample] = []
        let enumerator = fileManager.enumerator(
            at: historyDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "jsonl" {
                samples.append(contentsOf: parseFile(url, since: date, cache: cache))
            }
        }
        return samples
    }

    private func parseFile(_ fileURL: URL, since date: Date, cache: IncrementalReadCache?) -> [UsageSample] {
        if let cache {
            return parseFileIncremental(fileURL, since: date, cache: cache)
        } else {
            return parseFileFull(fileURL, since: date)
        }
    }

    private func parseFileFull(_ fileURL: URL, since date: Date) -> [UsageSample] {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else { return [] }

        var samples: [UsageSample] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let sample = parseLine(String(line), filePath: fileURL.path),
                  sample.timestamp >= date else { continue }
            samples.append(sample)
        }
        return samples
    }

    private func parseFileIncremental(
        _ fileURL: URL,
        since date: Date,
        cache: IncrementalReadCache
    ) -> [UsageSample] {
        let path = fileURL.path
        guard let attrs = try? fileManager.attributesOfItem(atPath: path),
              let mtime = attrs[.modificationDate] as? Date else { return [] }

        guard let fileHandle = FileHandle(forReadingAtPath: path) else { return [] }
        defer { fileHandle.closeFile() }

        let offset = cache.readOffsetSync(for: path, currentMtime: mtime)
        fileHandle.seek(toFileOffset: UInt64(offset))

        let newData = fileHandle.readDataToEndOfFile()
        let newOffset = Int64(offset) + Int64(newData.count)

        guard let text = String(data: newData, encoding: .utf8), !text.isEmpty else { return [] }

        var samples: [UsageSample] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let sample = parseLine(String(line), filePath: path),
                  sample.timestamp >= date else { continue }
            samples.append(sample)
        }

        cache.setOffsetSync(newOffset, path: path, mtime: mtime)
        return samples
    }

    private func parseLine(_ line: String, filePath: String) -> UsageSample? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        guard let role = obj["role"] as? String, role == "assistant",
              let usage = obj["usage"] as? [String: Any] else { return nil }

        let inputTokens  = usage["prompt_tokens"] as? Int ?? 0
        let outputTokens = usage["completion_tokens"] as? Int ?? 0
        guard inputTokens + outputTokens > 0 else { return nil }

        let modelID = obj["model"] as? String ?? "codex-unknown"

        guard let tsString = obj["created_at"] as? String ?? (obj["timestamp"] as? String),
              let timestamp = ISO8601DateFormatter().date(from: tsString) else { return nil }

        let id = obj["id"] as? String ?? UUID().uuidString
        return UsageSample(
            id: id,
            provider: provider,
            modelID: modelID,
            timestamp: timestamp,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            sourcePath: filePath
        )
    }
}
