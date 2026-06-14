import Foundation
import XCTest
@testable import TerminalCore

final class EnvironmentSanitizerTests: XCTestCase {
    func testBlockedNamesStripped() {
        let env: [String: String] = [
            "CLAUDECODE": "1",
            "GOOGLE_API_KEY": "key",
            "GEMINI_API_KEY": "key",
            "PATH": "/usr/bin",
        ]
        let result = EnvironmentSanitizer.sanitize(env)
        XCTAssertNil(result["CLAUDECODE"])
        XCTAssertNil(result["GOOGLE_API_KEY"])
        XCTAssertNil(result["GEMINI_API_KEY"])
        XCTAssertEqual(result["PATH"], "/usr/bin")
    }

    func testBlockedPrefixesStripped() {
        let env: [String: String] = [
            "ANTHROPIC_API_KEY": "key",
            "OPENAI_API_KEY": "key",
            "OPENROUTER_API_KEY": "key",
            "CLAUDE_CODE_MODEL": "claude",
            "AWS_SECRET_ACCESS_KEY": "key",
            "AWS_SECRET_SESSION_TOKEN": "token",
            "AZURE_OPENAI_API_KEY": "key",
            "COHERE_API_KEY": "key",
            "HF_TOKEN": "token",
            "TOGETHER_API_KEY": "key",
            "HUGGINGFACE_HUB_TOKEN": "token",
            "SAFE_VAR": "value",
        ]
        let result = EnvironmentSanitizer.sanitize(env)
        XCTAssertNil(result["ANTHROPIC_API_KEY"])
        XCTAssertNil(result["OPENAI_API_KEY"])
        XCTAssertNil(result["OPENROUTER_API_KEY"])
        XCTAssertNil(result["CLAUDE_CODE_MODEL"])
        XCTAssertNil(result["AWS_SECRET_ACCESS_KEY"])
        XCTAssertNil(result["AWS_SECRET_SESSION_TOKEN"])
        XCTAssertNil(result["AZURE_OPENAI_API_KEY"])
        XCTAssertNil(result["COHERE_API_KEY"])
        XCTAssertNil(result["HF_TOKEN"])
        XCTAssertNil(result["TOGETHER_API_KEY"])
        XCTAssertNil(result["HUGGINGFACE_HUB_TOKEN"])
        XCTAssertEqual(result["SAFE_VAR"], "value")
    }

    func testNonSensitivePassThrough() {
        let env: [String: String] = [
            "PATH": "/usr/bin",
            "HOME": "/Users/test",
            "TERM": "xterm-256color",
        ]
        let result = EnvironmentSanitizer.sanitize(env)
        XCTAssertEqual(result, env)
    }

    func testEmptyEnvironment() {
        let env: [String: String] = [:]
        let result = EnvironmentSanitizer.sanitize(env)
        XCTAssertTrue(result.isEmpty)
    }
}
