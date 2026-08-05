import Testing
import Foundation
@testable import UsageKit

// MARK: - ClaudeCodeReader

@Suite struct ClaudeCodeReaderTests {
    func makeTempDir() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("UsageKitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    func makeClaudeProjectDir(base: URL, project: String = "proj1") throws -> URL {
        let dir = base.appendingPathComponent(project)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func parsesAssistantEntriesWithUsage() async throws {
        let base = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }

        let projectDir = try makeClaudeProjectDir(base: base)
        let jsonl = """
        {"type":"human","uuid":"h1","timestamp":"2026-01-01T10:00:00Z","message":{"role":"user","content":"hi"}}
        {"type":"assistant","uuid":"a1","timestamp":"2026-01-01T10:00:01Z","message":{"id":"msg_1","role":"assistant","model":"claude-opus-4-5","content":[],"usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":20,"cache_read_input_tokens":10}}}
        {"type":"assistant","uuid":"a2","timestamp":"2026-01-01T10:00:02Z","message":{"role":"assistant","model":"claude-haiku-4-5","content":[],"usage":{"input_tokens":30,"output_tokens":15}}}
        """
        try jsonl.data(using: .utf8)!.write(to: projectDir.appendingPathComponent("session.jsonl"))

        let reader = ClaudeCodeReader(baseDirectory: base)
        let samples = try await reader.read(since: Date.distantPast)

        #expect(samples.count == 2)
        let s1 = samples.first { $0.id == "a1" }
        #expect(s1 != nil)
        #expect(s1?.inputTokens == 100)
        #expect(s1?.outputTokens == 50)
        #expect(s1?.cacheCreationTokens == 20)
        #expect(s1?.cacheReadTokens == 10)
        #expect(s1?.modelID == "claude-opus-4-5")
        #expect(s1?.project == "proj1")

        let s2 = samples.first { $0.id == "a2" }
        #expect(s2?.inputTokens == 30)
        #expect(s2?.outputTokens == 15)
        #expect(s2?.cacheCreationTokens == 0)
    }

    @Test func skipsEntriesBeforeSinceDate() async throws {
        let base = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }

        let projectDir = try makeClaudeProjectDir(base: base)
        let jsonl = """
        {"type":"assistant","uuid":"old","timestamp":"2020-01-01T00:00:00Z","message":{"model":"claude-opus-4-5","usage":{"input_tokens":5,"output_tokens":2}}}
        {"type":"assistant","uuid":"new","timestamp":"2026-06-01T00:00:00Z","message":{"model":"claude-opus-4-5","usage":{"input_tokens":10,"output_tokens":4}}}
        """
        try jsonl.data(using: .utf8)!.write(to: projectDir.appendingPathComponent("session.jsonl"))

        let since = ISO8601DateFormatter().date(from: "2024-01-01T00:00:00Z")!
        let reader = ClaudeCodeReader(baseDirectory: base)
        let samples = try await reader.read(since: since)

        #expect(samples.count == 1)
        #expect(samples[0].id == "new")
    }

    @Test func returnsEmptyWhenDirectoryMissing() async throws {
        let missing = URL(fileURLWithPath: "/tmp/definitely-does-not-exist-\(UUID().uuidString)")
        let reader = ClaudeCodeReader(baseDirectory: missing)
        let samples = try await reader.read(since: Date.distantPast)
        #expect(samples.isEmpty)
    }

    @Test func toleratesMalformedLines() async throws {
        let base = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }

        let projectDir = try makeClaudeProjectDir(base: base)
        let jsonl = """
        not json at all
        {"incomplete":
        {"type":"assistant","uuid":"ok","timestamp":"2026-06-01T00:00:00Z","message":{"model":"m","usage":{"input_tokens":1,"output_tokens":1}}}
        """
        try jsonl.data(using: .utf8)!.write(to: projectDir.appendingPathComponent("session.jsonl"))

        let reader = ClaudeCodeReader(baseDirectory: base)
        let samples = try await reader.read(since: Date.distantPast)
        #expect(samples.count == 1)
        #expect(samples[0].id == "ok")
    }

    @Test func skipsNonAssistantLinesWithoutFullJSONParse() async throws {
        let base = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }

        let projectDir = try makeClaudeProjectDir(base: base)
        let jsonl = """
        {"type":"human","uuid":"h1","timestamp":"2026-06-01T00:00:00Z","message":{"role":"user","content":"mentions assistant but is not one"}}
        {"type":"tool_use","uuid":"t1","timestamp":"2026-06-01T00:00:01Z"
        {"type": "assistant","uuid":"a1","timestamp":"2026-06-01T00:00:02Z","message":{"model":"m","usage":{"input_tokens":1,"output_tokens":1}}}
        {"type":"assistant","uuid":"a2","timestamp":"2026-06-01T00:00:03Z","message":{"model":"m","usage":{"input_tokens":2,"output_tokens":2}}}
        """
        try jsonl.data(using: .utf8)!.write(to: projectDir.appendingPathComponent("session.jsonl"))

        let reader = ClaudeCodeReader(baseDirectory: base)
        let samples = try await reader.read(since: Date.distantPast)

        #expect(samples.count == 2)
        #expect(Set(samples.map(\.id)) == ["a1", "a2"])
    }

    @Test func skipsZeroTokenEntries() async throws {
        let base = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }

        let projectDir = try makeClaudeProjectDir(base: base)
        let jsonl = """
        {"type":"assistant","uuid":"zero","timestamp":"2026-06-01T00:00:00Z","message":{"model":"m","usage":{"input_tokens":0,"output_tokens":0}}}
        {"type":"assistant","uuid":"real","timestamp":"2026-06-01T00:00:01Z","message":{"model":"m","usage":{"input_tokens":5,"output_tokens":3}}}
        """
        try jsonl.data(using: .utf8)!.write(to: projectDir.appendingPathComponent("session.jsonl"))

        let reader = ClaudeCodeReader(baseDirectory: base)
        let samples = try await reader.read(since: Date.distantPast)
        #expect(samples.count == 1)
        #expect(samples[0].id == "real")
    }

    @Test func skipsOversizedTranscriptOnFullRead() async throws {
        let base = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }

        let projectDir = try makeClaudeProjectDir(base: base)
        let jsonl = """
        {"type":"assistant","uuid":"big","timestamp":"2026-06-01T00:00:00Z","message":{"model":"claude-opus-4-5","usage":{"input_tokens":10,"output_tokens":4}}}
        """
        try jsonl.data(using: .utf8)!.write(to: projectDir.appendingPathComponent("session.jsonl"))

        // Tiny cap: even a small transcript exceeds it, so the full-read path
        // must skip the file instead of loading it.
        let reader = ClaudeCodeReader(baseDirectory: base, maxFileSizeBytes: 10)
        let samples = try await reader.read(since: Date.distantPast)
        #expect(samples.isEmpty)
    }

    @Test func skipsFilesBeyondMaxDepth() async throws {
        let base = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }

        // Session at depth 1 (base/proj/session.jsonl) is found...
        let projectDir = try makeClaudeProjectDir(base: base)
        let shallow = """
        {"type":"assistant","uuid":"shallow","timestamp":"2026-06-01T00:00:00Z","message":{"model":"claude-opus-4-5","usage":{"input_tokens":5,"output_tokens":2}}}
        """
        try shallow.data(using: .utf8)!.write(to: projectDir.appendingPathComponent("s.jsonl"))

        // ...but a transcript nested deeper than maxDepth is not enumerated.
        let deepDir = base.appendingPathComponent("p1/p2/p3/p4/p5")
        try FileManager.default.createDirectory(at: deepDir, withIntermediateDirectories: true)
        let deep = """
        {"type":"assistant","uuid":"deep","timestamp":"2026-06-01T00:00:00Z","message":{"model":"claude-opus-4-5","usage":{"input_tokens":9,"output_tokens":3}}}
        """
        try deep.data(using: .utf8)!.write(to: deepDir.appendingPathComponent("deep.jsonl"))

        let reader = ClaudeCodeReader(baseDirectory: base, maxDepth: 3)
        let samples = try await reader.read(since: Date.distantPast)
        #expect(samples.count == 1)
        #expect(samples[0].id == "shallow")
    }

    @Test func respectsDefaultSizeAndDepthLimits() async throws {
        let base = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }

        let projectDir = try makeClaudeProjectDir(base: base)
        let jsonl = """
        {"type":"assistant","uuid":"ok","timestamp":"2026-06-01T00:00:00Z","message":{"model":"claude-opus-4-5","usage":{"input_tokens":7,"output_tokens":1}}}
        """
        try jsonl.data(using: .utf8)!.write(to: projectDir.appendingPathComponent("session.jsonl"))

        // Default limits (64 MiB / depth 4) must not break normal reads.
        let reader = ClaudeCodeReader(baseDirectory: base)
        let samples = try await reader.read(since: Date.distantPast)
        #expect(samples.count == 1)
        #expect(samples[0].id == "ok")
    }
}

// MARK: - CodexReader

@Suite struct CodexReaderTests {
    @Test func returnsEmptyWhenHistoryDirMissing() async throws {
        let missing = URL(fileURLWithPath: "/tmp/no-codex-\(UUID().uuidString)")
        let reader = CodexReader(historyDirectory: missing)
        let samples = try await reader.read(since: Date.distantPast)
        #expect(samples.isEmpty)
    }

    @Test func parsesAssistantLines() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let jsonl = """
        {"role":"user","content":"hello"}
        {"role":"assistant","id":"cx1","model":"o4-mini","created_at":"2026-06-01T00:00:00Z","usage":{"prompt_tokens":20,"completion_tokens":10}}
        """
        try jsonl.data(using: .utf8)!.write(to: tmp.appendingPathComponent("s1.jsonl"))

        let reader = CodexReader(historyDirectory: tmp)
        let samples = try await reader.read(since: Date.distantPast)
        #expect(samples.count == 1)
        #expect(samples[0].inputTokens == 20)
        #expect(samples[0].outputTokens == 10)
        #expect(samples[0].modelID == "o4-mini")
    }
}

// MARK: - GeminiCLIReader

@Suite struct GeminiCLIReaderTests {
    @Test func returnsEmptyWhenDirMissing() async throws {
        let missing = URL(fileURLWithPath: "/tmp/no-gemini-\(UUID().uuidString)")
        let reader = GeminiCLIReader(logsDirectory: missing)
        let samples = try await reader.read(since: Date.distantPast)
        #expect(samples.isEmpty)
    }

    @Test func parsesModelTurnsFromJSONL() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("gemini-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let jsonl = """
        {"role":"user","timestamp":"2026-06-01T00:00:00Z","parts":[{"text":"hello"}]}
        {"role":"model","id":"g1","model":"gemini-2.0-flash","timestamp":"2026-06-01T00:00:01Z","usageMetadata":{"promptTokenCount":50,"candidatesTokenCount":25}}
        """
        try jsonl.data(using: .utf8)!.write(to: tmp.appendingPathComponent("conv1.jsonl"))

        let reader = GeminiCLIReader(logsDirectory: tmp)
        let samples = try await reader.read(since: Date.distantPast)
        #expect(samples.count == 1)
        #expect(samples[0].inputTokens == 50)
        #expect(samples[0].outputTokens == 25)
    }
}
