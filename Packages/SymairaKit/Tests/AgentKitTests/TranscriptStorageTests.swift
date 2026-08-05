import Foundation
import XCTest
@testable import AgentKit

final class TranscriptStorageTests: XCTestCase {
    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
        tmpDir = nil
    }

    private func makeEntry(id: String) -> TranscriptEntry {
        TranscriptEntry(
            id: id,
            timestamp: ISO8601DateFormatter().date(from: "2026-06-01T10:00:00Z")!,
            sessionId: "session-1",
            content: [
                TranscriptMessage(role: .user, content: "hello"),
                TranscriptMessage(role: .assistant, content: "hi", toolCalls: [
                    ToolCall(name: "shell", arguments: "ls")
                ])
            ],
            metadata: TranscriptMetadata(repositoryURL: "https://example.com/repo", branch: "main")
        )
    }

    func testSaveAndLoadRoundTrip() throws {
        let storage = TranscriptStorage(storageDirectory: tmpDir)
        let entry = makeEntry(id: "t-1")
        try storage.save(entry)

        let loaded = storage.load(id: "t-1")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.id, "t-1")
        XCTAssertEqual(loaded?.sessionId, "session-1")
        XCTAssertEqual(loaded?.content.count, 2)
        XCTAssertEqual(loaded?.content[0].role, .user)
        XCTAssertEqual(loaded?.content[1].toolCalls?.first?.name, "shell")
        XCTAssertEqual(loaded?.metadata.repositoryURL, "https://example.com/repo")
    }

    func testLoadMissingReturnsNil() {
        let storage = TranscriptStorage(storageDirectory: tmpDir)
        XCTAssertNil(storage.load(id: "does-not-exist"))
    }

    func testDeleteRemovesFile() throws {
        let storage = TranscriptStorage(storageDirectory: tmpDir)
        try storage.save(makeEntry(id: "t-del"))
        XCTAssertNotNil(storage.load(id: "t-del"))
        try storage.delete(id: "t-del")
        XCTAssertNil(storage.load(id: "t-del"))
    }

    func testListReturnsNewestFirst() async throws {
        let storage = TranscriptStorage(storageDirectory: tmpDir)
        try storage.save(makeEntry(id: "old"))
        // Give the second entry a distinctly newer mtime by writing it last.
        try await Task.sleep(nanoseconds: 50_000_000)
        try storage.save(makeEntry(id: "new"))

        let list = storage.list()
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list.first?.id, "new")
    }

    func testListLimitAndOffset() throws {
        let storage = TranscriptStorage(storageDirectory: tmpDir)
        try storage.save(makeEntry(id: "a"))
        try storage.save(makeEntry(id: "b"))
        try storage.save(makeEntry(id: "c"))

        let limited = storage.list(limit: 2)
        XCTAssertEqual(limited.count, 2)

        let offset = storage.list(limit: 1, offset: 2)
        XCTAssertEqual(offset.count, 1)
    }

    func testListEmptyDirectory() {
        let storage = TranscriptStorage(storageDirectory: tmpDir)
        XCTAssertTrue(storage.list().isEmpty)
    }
}
