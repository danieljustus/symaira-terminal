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

    func testSaveFailureIsReportedToHandler() async throws {
        // Storage directory path is occupied by a regular file — the directory
        // creation inside performSave must fail and surface the error.
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("SymairaTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let blockerFile = tmpDir.appendingPathComponent("blocked")
        try Data("not a directory".utf8).write(to: blockerFile)

        let persistence = SessionPersistence(storageDirectory: blockerFile, debounceInterval: 0.05)

        let state = SessionState(
            panes: [PaneState(workingDirectory: "/Users/test")],
            layout: .pane(index: 0),
            windowFrame: CodableRect(x: 0, y: 0, width: 1024, height: 768)
        )

        let errorReported = expectation(description: "save error reported")
        persistence.saveErrorHandler = { _ in
            errorReported.fulfill()
        }

        try persistence.save(state)
        await fulfillment(of: [errorReported], timeout: 2.0)
    }

    func testConcurrentSavesCoalesceWithoutCrash() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("SymairaTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let persistence = SessionPersistence(storageDirectory: tmpDir, debounceInterval: 0.05)

        let states = (0..<20).map { i in
            SessionState(
                panes: [PaneState(workingDirectory: "/Users/test\(i)")],
                layout: .pane(index: 0),
                windowFrame: CodableRect(x: 0, y: 0, width: 1024, height: 768)
            )
        }

        // Fire saves from multiple tasks to exercise the pending-state lock.
        // Execution order is not guaranteed, so the debounced write may land on
        // any of the states — the invariant is that the store stays consistent.
        await withTaskGroup(of: Void.self) { group in
            for state in states {
                group.addTask {
                    try? persistence.save(state)
                }
            }
        }

        // Let the last debounced write flush, then a termination save must win.
        try await Task.sleep(nanoseconds: 200_000_000)
        let finalState = SessionState(
            panes: [PaneState(workingDirectory: "/Users/test-final")],
            layout: .pane(index: 0),
            windowFrame: CodableRect(x: 0, y: 0, width: 1024, height: 768)
        )
        try persistence.saveImmediately(finalState)

        let loaded = persistence.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.panes.first?.workingDirectory, "/Users/test-final")
    }
}
