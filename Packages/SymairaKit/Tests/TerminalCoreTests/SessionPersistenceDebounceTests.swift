import Foundation
@testable import TerminalCore
import XCTest

final class SessionPersistenceDebounceTests: XCTestCase {
    func testDebouncedSave() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("SymairaTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let persistence = SessionPersistence(storageDirectory: tmpDir)

        let state1 = SessionState(
            panes: [PaneState(workingDirectory: "/Users/test1")],
            layout: .pane(index: 0),
            windowFrame: CodableRect(x: 0, y: 0, width: 1024, height: 768)
        )

        let state2 = SessionState(
            panes: [PaneState(workingDirectory: "/Users/test2")],
            layout: .pane(index: 0),
            windowFrame: CodableRect(x: 0, y: 0, width: 1024, height: 768)
        )

        try persistence.save(state1)
        try persistence.save(state2)

        try await Task.sleep(nanoseconds: 600_000_000)

        let loaded = persistence.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.panes.first?.workingDirectory, "/Users/test2")
    }

    func testImmediateSaveOnTermination() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("SymairaTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let persistence = SessionPersistence(storageDirectory: tmpDir)

        let state = SessionState(
            panes: [PaneState(workingDirectory: "/Users/test")],
            layout: .pane(index: 0),
            windowFrame: CodableRect(x: 0, y: 0, width: 1024, height: 768)
        )

        try persistence.save(state)
        try persistence.saveImmediately(state)

        try await Task.sleep(nanoseconds: 100_000_000)

        let loaded = persistence.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.panes.first?.workingDirectory, "/Users/test")
    }
}
