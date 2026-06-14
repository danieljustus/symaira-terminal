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
    private let fileManager: FileManager

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
                samples.append(contentsOf: parseJSONL(url, since: date))
            } else if ext == "json" {
                samples.append(contentsOf: parseJSONArray(url, since: date))
            }
        }
        return samples
    }

    private func parseJSONL(_ fileURL: URL, since date: Date) -> [UsageSample] {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else { return [] }
        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { parseTurn(String($0), filePath: fileURL.path) }
            .filter { $0.timestamp >= date }
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
