import Foundation
@testable import TerminalCore
import XCTest

final class SessionPersistenceDebounceTests: XCTestCase {
    // Test that rapid saves are debounced
    func testDebouncedSave() async throws {
        // Create a temporary directory for testing
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("SymairaTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Create a custom SessionPersistence instance with debouncing
        let persistence = SessionPersistence(storageDirectory: tmpDir)
        
        // Create a test state
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
        
        // Rapidly save two states
        try persistence.save(state1)
        try persistence.save(state2)
        
        // Wait for debounce window to complete
        try await Task.sleep(nanoseconds: 600_000_000) // 600ms > 500ms debounce
        
        // Only the last state should be saved
        let loaded = persistence.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.panes.first?.workingDirectory, "/Users/test2")
    }
    
    // Test that app termination triggers immediate save
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
        
        // Save with debounce
        try persistence.save(state)
        
        // Immediately call saveImmediately (simulating app termination)
        try persistence.saveImmediately(state)
        
        // Wait a bit to ensure immediate save happened
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // State should be saved immediately
        let loaded = persistence.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.panes.first?.workingDirectory, "/Users/test")
    }
}