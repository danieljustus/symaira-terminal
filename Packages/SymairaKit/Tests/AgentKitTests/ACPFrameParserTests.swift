import XCTest
@testable import AgentKit

final class ACPFrameParserTests: XCTestCase {
    private func frame(_ jsonString: String) -> Data {
        let body = jsonString.data(using: .utf8)!
        let header = "Content-Length: \(body.count)\r\n\r\n"
        return header.data(using: .utf8)! + body
    }

    func testSingleMessage() {
        var parser = ACPFrameParser()
        let msg = #"{"jsonrpc":"2.0","method":"test","id":1}"#
        parser.feed(frame(msg))

        let result = parser.nextMessage()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?["method"] as? String, "test")
        XCTAssertEqual(result?["id"] as? Int, 1)
        XCTAssertTrue(parser.isEmpty)
    }

    func testBackToBackMessages() {
        var parser = ACPFrameParser()
        let msg1 = #"{"jsonrpc":"2.0","method":"first","id":1}"#
        let msg2 = #"{"jsonrpc":"2.0","method":"second","id":2}"#
        parser.feed(frame(msg1) + frame(msg2))

        let r1 = parser.nextMessage()
        XCTAssertNotNil(r1)
        XCTAssertEqual(r1?["method"] as? String, "first")

        let r2 = parser.nextMessage()
        XCTAssertNotNil(r2)
        XCTAssertEqual(r2?["method"] as? String, "second")

        XCTAssertTrue(parser.isEmpty)
    }

    func testSplitHeader() {
        var parser = ACPFrameParser()
        let full = frame(#"{"jsonrpc":"2.0","method":"test"}"#)
        let mid = full.index(full.startIndex, offsetBy: 10)
        parser.feed(full[..<mid])
        XCTAssertNil(parser.nextMessage())

        parser.feed(full[mid...])
        let result = parser.nextMessage()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?["method"] as? String, "test")
    }

    func testSplitBody() {
        var parser = ACPFrameParser()
        let full = frame(#"{"jsonrpc":"2.0","method":"test"}"#)
        let headerEnd = full.range(of: Data("\r\n\r\n".utf8))!.upperBound
        parser.feed(full[..<headerEnd])
        XCTAssertNil(parser.nextMessage())

        parser.feed(full[headerEnd...])
        let result = parser.nextMessage()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?["method"] as? String, "test")
    }

    func testMalformedContentLength() {
        var parser = ACPFrameParser()
        let bad = "Content-Length: abc\r\n\r\n{}"
        parser.feed(bad.data(using: .utf8)!)
        XCTAssertNil(parser.nextMessage())
    }

    func testOversizedContentLength() {
        var parser = ACPFrameParser(maxContentLength: 100)
        let body = String(repeating: "x", count: 200)
        let msg = #"{"data":""# + body + #""}"#
        parser.feed(frame(msg))
        XCTAssertNil(parser.nextMessage())
    }

    func testZeroContentLength() {
        var parser = ACPFrameParser()
        let msg = "Content-Length: 0\r\n\r\n"
        parser.feed(msg.data(using: .utf8)!)
        XCTAssertNil(parser.nextMessage())
    }

    func testPartialThenMore() {
        var parser = ACPFrameParser()
        let msg = #"{"jsonrpc":"2.0","method":"partial"}"#
        let full = frame(msg)
        parser.feed(full[..<5])
        XCTAssertNil(parser.nextMessage())

        parser.feed(full[5..<15])
        XCTAssertNil(parser.nextMessage())

        parser.feed(full[15...])
        let result = parser.nextMessage()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?["method"] as? String, "partial")
    }

    // MARK: - Buffer bounding

    func testEndlessHeaderWithoutTerminatorResetsBuffer() {
        var parser = ACPFrameParser(maxContentLength: 100)
        // 64 KiB stays below the cap (maxContentLength + 64 KiB) — the parser
        // keeps buffering in the hope of a header terminator.
        let junk = Data(repeating: 0x61, count: 1024) // 'a'
        for _ in 0..<64 { parser.feed(junk) }
        XCTAssertNil(parser.nextMessage())

        // Crossing the cap resets the malformed stream instead of growing
        // memory without limit.
        parser.feed(junk)
        XCTAssertTrue(parser.isEmpty, "buffer must be reset after exceeding the cap")
        XCTAssertNil(parser.nextMessage())
    }

    func testResyncAfterBufferReset() {
        var parser = ACPFrameParser(maxContentLength: 100)
        let junk = Data(repeating: 0x61, count: 1024)
        for _ in 0..<65 { parser.feed(junk) } // ~65 KiB crosses the cap; stream dropped
        XCTAssertTrue(parser.isEmpty)

        // A well-formed frame fed after the reset must parse normally.
        let msg = #"{"jsonrpc":"2.0","method":"after-reset","id":7}"#
        parser.feed(frame(msg))
        let result = parser.nextMessage()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?["method"] as? String, "after-reset")
        XCTAssertTrue(parser.isEmpty)
    }

    func testLargeFragmentedFrameWithinCapStillParses() {
        var parser = ACPFrameParser(maxContentLength: 1024 * 1024)
        let body = #"{"jsonrpc":"2.0","method":"big","data":""# + String(repeating: "x", count: 512 * 1024) + #""}"#
        let full = frame(body)
        // Feed in small chunks, staying well below the cap — fragmented delivery
        // of a legitimate large frame must keep working.
        var offset = 0
        while offset < full.count {
            let chunkEnd = min(offset + 4096, full.count)
            parser.feed(full[offset..<chunkEnd])
            offset = chunkEnd
            if offset < full.count {
                XCTAssertNil(parser.nextMessage(), "no complete frame before all bytes arrive")
            }
        }
        let result = parser.nextMessage()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?["method"] as? String, "big")
        XCTAssertTrue(parser.isEmpty)
    }
}
