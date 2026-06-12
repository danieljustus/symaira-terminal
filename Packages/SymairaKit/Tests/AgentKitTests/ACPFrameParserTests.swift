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
        let headerEnd = full.range(of: "\r\n\r\n".data(using: .utf8)!)!.upperBound
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
}
