import Foundation
@testable import TerminalCore
import XCTest

final class SessionStateTests: XCTestCase {
    func testPaneStateDefaults() {
        let pane = PaneState()
        XCTAssertEqual(pane.executablePath, "/bin/zsh")
        XCTAssertEqual(pane.arguments, ["-l"])
        XCTAssertNil(pane.workingDirectory)
        XCTAssertEqual(pane.columns, 80)
        XCTAssertEqual(pane.rows, 24)
    }

    func testSplitNodePaneRoundtrip() throws {
        let original = SplitNode.pane(index: 0)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SplitNode.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testSplitNodeNestedRoundtrip() throws {
        let original = SplitNode.split(
            orientation: .horizontal,
            ratio: 0.6,
            left: .pane(index: 0),
            right: .split(
                orientation: .vertical,
                ratio: 0.4,
                left: .pane(index: 1),
                right: .pane(index: 2)
            )
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SplitNode.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testSessionStateRoundtrip() throws {
        let state = SessionState(
            panes: [
                PaneState(executablePath: "/bin/zsh", workingDirectory: "/tmp"),
                PaneState(executablePath: "/bin/bash", columns: 120, rows: 40),
            ],
            layout: .split(
                orientation: .horizontal,
                ratio: 0.5,
                left: .pane(index: 0),
                right: .pane(index: 1)
            ),
            windowFrame: CodableRect(x: 100, y: 200, width: 1200, height: 800)
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(SessionState.self, from: data)
        XCTAssertEqual(state, decoded)
        XCTAssertEqual(decoded.panes.count, 2)
        XCTAssertEqual(decoded.panes[0].executablePath, "/bin/zsh")
        XCTAssertEqual(decoded.panes[1].columns, 120)
        XCTAssertEqual(decoded.windowFrame.width, 1200)
    }

    func testCodableRectFromNSRect() {
        let rect = CodableRect(NSRect(x: 10, y: 20, width: 300, height: 400))
        XCTAssertEqual(rect.x, 10)
        XCTAssertEqual(rect.y, 20)
        XCTAssertEqual(rect.width, 300)
        XCTAssertEqual(rect.height, 400)
        XCTAssertEqual(rect.nsRect, NSRect(x: 10, y: 20, width: 300, height: 400))
    }

    func testSessionPersistenceSaveAndLoad() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("SymairaTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let state = SessionState(
            panes: [PaneState(workingDirectory: "/Users/test")],
            layout: .pane(index: 0),
            windowFrame: CodableRect(x: 0, y: 0, width: 1024, height: 768)
        )

        let fileURL = tmpDir.appendingPathComponent("sessions.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(state)
        try data.write(to: fileURL)

        let loaded = try JSONDecoder().decode(SessionState.self, from: Data(contentsOf: fileURL))
        XCTAssertEqual(state, loaded)
    }

    func testSplitOrientationRawValues() {
        XCTAssertEqual(SplitOrientation.horizontal.rawValue, "horizontal")
        XCTAssertEqual(SplitOrientation.vertical.rawValue, "vertical")
    }
}
