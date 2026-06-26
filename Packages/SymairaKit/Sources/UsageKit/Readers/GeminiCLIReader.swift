import Foundation

/// Reads Gemini CLI usage from its local conversation log files.
///
/// Gemini CLI (google/gemini-cli) stores session logs under:
///   ~/.gemini/conversations/<session-id>.json  (or `.jsonl`)
///
/// Lines/objects with `role == "model"` may carry `usageMetadata` with
/// `promptTokenCount` and `candidatesTokenCount`.
///
/// Log format is not publicly stable — the reader is intentionally lenient.
public struct GeminiCLIReader: UsageReader, Sendable {
    public let provider: UsageProvider = UsageProviders.geminiCLI

    private let logsDirectory: URL
    nonisolated(unsafe) private let fileManager: FileManager

    public init(
        logsDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.logsDirectory = logsDirectory
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".gemini/conversations")
        self.fileManager = fileManager
    }

    public func read(since date: Date) async throws -> [UsageSample] {
        guard fileManager.fileExists(atPath: logsDirectory.path) else { return [] }
        var samples: [UsageSample] = []
        let enumerator = fileManager.enumerator(
            at: logsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            let ext = url.pathExtension
            if ext == "jsonl" {
                samples.append(contentsOf: parseJSONL(url, since: date, cache: nil))
            } else if ext == "json" {
                samples.append(contentsOf: parseJSONArray(url, since: date))
            }
        }
        return samples
    }

    public func read(since date: Date, cache: IncrementalReadCache?) async throws -> [UsageSample] {
        guard fileManager.fileExists(atPath: logsDirectory.path) else { return [] }
        var samples: [UsageSample] = []
        let enumerator = fileManager.enumerator(
            at: logsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            let ext = url.pathExtension
            if ext == "jsonl" {
                samples.append(contentsOf: parseJSONL(url, since: date, cache: cache))
            } else if ext == "json" {
                samples.append(contentsOf: parseJSONArray(url, since: date))
            }
        }
        return samples
    }

    private func parseJSONL(_ fileURL: URL, since date: Date, cache: IncrementalReadCache?) -> [UsageSample] {
        if let cache {
            return parseJSONLIncremental(fileURL, since: date, cache: cache)
        } else {
            return parseJSONLFull(fileURL, since: date)
        }
    }

    private func parseJSONLFull(_ fileURL: URL, since date: Date) -> [UsageSample] {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else { return [] }
        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { parseTurn(String($0), filePath: fileURL.path) }
            .filter { $0.timestamp >= date }
    }

    private func parseJSONLIncremental(
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

        let samples = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { parseTurn(String($0), filePath: path) }
            .filter { $0.timestamp >= date }

        cache.setOffsetSync(newOffset, path: path, mtime: mtime)
        return samples
    }

    private func parseJSONArray(_ fileURL: URL, since date: Date) -> [UsageSample] {
        guard let data = try? Data(contentsOf: fileURL),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return array
            .compactMap { parseTurnObject($0, filePath: fileURL.path) }
            .filter { $0.timestamp >= date }
    }

    private func parseTurn(_ line: String, filePath: String) -> UsageSample? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return parseTurnObject(obj, filePath: filePath)
    }

    private func parseTurnObject(_ obj: [String: Any], filePath: String) -> UsageSample? {
        guard let role = obj["role"] as? String, role == "model",
              let meta = obj["usageMetadata"] as? [String: Any] else { return nil }

        let inputTokens  = meta["promptTokenCount"] as? Int ?? 0
        let outputTokens = meta["candidatesTokenCount"] as? Int ?? 0
        guard inputTokens + outputTokens > 0 else { return nil }

        let modelID = obj["model"] as? String ?? "gemini-unknown"

        guard let tsString = obj["timestamp"] as? String ?? (obj["created_at"] as? String),
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
