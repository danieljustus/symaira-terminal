import XCTest
@testable import WorktreeKit

final class WorkspaceMonitorTests: XCTestCase {

    // MARK: - parseProcessTree

    func testParseProcessTreeBasic() {
        let output = """
          1     0
        123    45
        456   123
        """
        let map = WorkspaceMonitor.parseProcessTree(output)
        XCTAssertEqual(map[1], 0)
        XCTAssertEqual(map[123], 45)
        XCTAssertEqual(map[456], 123)
    }

    func testParseProcessTreeIgnoresMalformedLines() {
        let output = "notanumber 0\n100 200\n"
        let map = WorkspaceMonitor.parseProcessTree(output)
        XCTAssertNil(map[0])          // "notanumber" must not crash
        XCTAssertEqual(map[100], 200)
    }

    func testParseProcessTreeEmptyInput() {
        XCTAssertTrue(WorkspaceMonitor.parseProcessTree("").isEmpty)
    }

    // MARK: - parseListeningPorts

    func testParseListeningPortsBasic() {
        // lsof -iTCP -sTCP:LISTEN -P -n output format (columns 0-8):
        // COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
        let output = """
COMMAND   PID   USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
node     1234   alice  32u  IPv4  12345      0t0  TCP *:3000 (LISTEN)
python   5678   alice  10u  IPv6  23456      0t0  TCP *:8080 (LISTEN)
"""
        let ports = WorkspaceMonitor.parseListeningPorts(output)
        XCTAssertEqual(ports.count, 2)
        XCTAssertEqual(ports[0].pid, 1234)
        XCTAssertEqual(ports[0].port, 3000)
        XCTAssertEqual(ports[1].pid, 5678)
        XCTAssertEqual(ports[1].port, 8080)
    }

    func testParseListeningPortsSkipsHeaderAndEmptyLines() {
        let output = "COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\n\n"
        XCTAssertTrue(WorkspaceMonitor.parseListeningPorts(output).isEmpty)
    }

    func testParseListeningPortsIgnoresMalformedLines() {
        let output = "bad line\nnot enough columns\n"
        XCTAssertTrue(WorkspaceMonitor.parseListeningPorts(output).isEmpty)
    }

    // MARK: - isDescendant

    func testIsDescendantDirectParent() {
        let map: [Int32: Int32] = [42: 1]
        XCTAssertTrue(WorkspaceMonitor.isDescendant(pid: 42, parentPID: 1, parentMap: map))
    }

    func testIsDescendantTransitive() {
        let map: [Int32: Int32] = [3: 2, 2: 1]
        XCTAssertTrue(WorkspaceMonitor.isDescendant(pid: 3, parentPID: 1, parentMap: map))
    }

    func testIsDescendantUnrelated() {
        let map: [Int32: Int32] = [10: 5, 20: 15]
        XCTAssertFalse(WorkspaceMonitor.isDescendant(pid: 10, parentPID: 20, parentMap: map))
    }

    func testIsDescendantCycleDoesNotHang() {
        // Pathological: pid points back to itself — must not infinite-loop.
        let map: [Int32: Int32] = [1: 1]
        XCTAssertFalse(WorkspaceMonitor.isDescendant(pid: 1, parentPID: 99, parentMap: map))
    }
}
