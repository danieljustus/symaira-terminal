import XCTest
@testable import AgentKit

final class ACPClientStderrRedactionTests: XCTestCase {
    func testRedactsAnthropicKeyInStderrChunk() {
        let chunk = "curl -v https://api.example.com -H \"Authorization: Bearer sk-ant-api03-ABCDEFghijklmnop1234567890\""
        let redacted = ACPClient.redactedStderr(chunk)
        XCTAssertFalse(redacted.contains("sk-ant-api03"))
        XCTAssertTrue(redacted.contains("[REDACTED"))
    }

    func testRedactsGitHubToken() {
        let chunk = "debug: token=ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnop"
        let redacted = ACPClient.redactedStderr(chunk)
        XCTAssertFalse(redacted.contains("ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ"))
        XCTAssertTrue(redacted.contains("[REDACTED"))
    }

    func testRedactsBearerTokenInHeader() {
        let chunk = "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.abcdefghijklmnopqrstuvwxyz"
        let redacted = ACPClient.redactedStderr(chunk)
        XCTAssertFalse(redacted.contains("eyJhbGciOiJIUzI1Ni"))
        XCTAssertTrue(redacted.contains("[REDACTED"))
    }

    func testKeepsPlainDiagnosticsReadable() {
        let chunk = "info: connecting to provider endpoint in 3s"
        let redacted = ACPClient.redactedStderr(chunk)
        XCTAssertEqual(redacted, chunk)
    }
}
