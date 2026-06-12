import XCTest
@testable import SymairaTerminal

final class ScrollbackBufferTests: XCTestCase {

    func testPruneByByteCount() {
        let buf = ScrollbackBuffer(maxLines: 10_000, maxBytes: 100)
        let line = Array(repeating: UInt8(ascii: "A"), count: 50) + [UInt8(ascii: "\n")]
        buf.append(line)
        buf.append(line)
        buf.append(line)
        XCTAssert(buf.currentText?.utf8.count ?? 0 <= 100, "Buffer should be pruned to under maxBytes")
    }

    func testLargeSingleLinePrunedByByteLimit() {
        let buf = ScrollbackBuffer(maxLines: 10_000, maxBytes: 1024)
        let hugeLine = Array(repeating: UInt8(ascii: "X"), count: 10_000) + [UInt8(ascii: "\n")]
        buf.append(hugeLine)
        XCTAssert(buf.currentText?.utf8.count ?? 0 <= 1024, "Single large line should be pruned by byte limit")
    }

    func testSearchAfterBytePruning() {
        let buf = ScrollbackBuffer(maxLines: 10_000, maxBytes: 200)
        buf.append(Array("first line\n".utf8))
        buf.append(Array("second line\n".utf8))
        buf.append(Array("third line\n".utf8))
        buf.append(Array("fourth line with needle\n".utf8))
        let matches = buf.searchText("needle")
        XCTAssertFalse(matches.isEmpty, "Search should find 'needle' after pruning")
        XCTAssertEqual(matches.first?.lineNumber, 4)
    }

    func testLineAndByteLimitsTogether() {
        let buf = ScrollbackBuffer(maxLines: 3, maxBytes: 10_000)
        for i in 0..<5 {
            buf.append(Array("line \(i)\n".utf8))
        }
        let text = buf.currentText ?? ""
        let lineCount = text.split(separator: "\n").count
        XCTAssert(lineCount <= 3, "Should respect maxLines limit")
    }

    func testBinaryOutput() {
        let buf = ScrollbackBuffer(maxLines: 10_000, maxBytes: 1024)
        let binary = Array(0..<200).map { UInt8($0 % 256) }
        buf.append(binary)
        XCTAssert(buf.currentText?.utf8.count ?? 0 <= 1024, "Binary data should be pruned by byte limit")
    }

    func testSearchPreservesLineNumbersAfterPruning() {
        let buf = ScrollbackBuffer(maxLines: 10_000, maxBytes: 100)
        buf.append(Array("aaa\n".utf8))
        buf.append(Array("bbb\n".utf8))
        buf.append(Array("ccc\n".utf8))
        buf.append(Array("ddd\n".utf8))
        buf.append(Array("eee target\n".utf8))
        let matches = buf.searchText("target")
        if let m = matches.first {
            XCTAssert(m.lineNumber >= 1, "Line number should be valid after pruning")
            XCTAssertTrue(m.line.contains("target"), "Matched line should contain the query")
        }
    }

    func testDefaultMaxBytes() {
        let buf = ScrollbackBuffer()
        let data = Array(repeating: UInt8(ascii: "A"), count: 100)
        buf.append(data)
        XCTAssertEqual(buf.currentText?.utf8.count, 100)
    }

    func testClearResetsBuffer() {
        let buf = ScrollbackBuffer(maxLines: 10, maxBytes: 50)
        buf.append(Array("some data\n".utf8))
        buf.clear()
        XCTAssertNil(buf.currentText)
        XCTAssertEqual(buf.searchText("data").count, 0)
    }
}
