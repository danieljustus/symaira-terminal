import XCTest
@testable import TerminalCore

final class SecretRedactorTests: XCTestCase {
    private var redactor: SecretRedactor!

    override func setUp() {
        super.setUp()
        redactor = SecretRedactor()
    }

    func testRedactsAnthropicKey() {
        let input = "Error with key sk-ant-api03-ABCDEFghijklmnop1234567890 in output"
        let result = redactor.redact(input)
        XCTAssertFalse(result.text.contains("sk-ant-"))
        XCTAssertTrue(result.text.contains("[REDACTED:anthropic-key]"))
        XCTAssertEqual(result.redactionCount, 1)
    }

    func testRedactsOpenAIKey() {
        let input = "Error with key sk-ABCDEFghijklmnop1234567890ABCDEF in output"
        let result = redactor.redact(input)
        XCTAssertFalse(result.text.contains("sk-ABCDEF"))
        XCTAssertTrue(result.text.contains("[REDACTED:openai-key]"))
    }

    func testRedactsGitHubToken() {
        let input = "token: ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij"
        let result = redactor.redact(input)
        XCTAssertFalse(result.text.contains("ghp_"))
        XCTAssertTrue(result.text.contains("[REDACTED:github-token]"))
    }

    func testRedactsGitLabToken() {
        let input = "GITLAB_TOKEN=glpat-ABCDEFGHIJKLMNOPQRST"
        let result = redactor.redact(input)
        XCTAssertFalse(result.text.contains("glpat-"))
        XCTAssertTrue(result.text.contains("[REDACTED:gitlab-token]"))
    }

    func testRedactsSlackToken() {
        let input = "SLACK_TOKEN=xoxb-TEST1234567-TESTTOKENABCDEFGHIJ"
        let result = redactor.redact(input)
        XCTAssertFalse(result.text.contains("xoxb-TEST"))
        XCTAssertTrue(result.text.contains("[REDACTED:slack-token]"))
    }

    func testRedactsStripeKey() {
        let input = "stripe_key=sk_test_TESTKEYABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let result = redactor.redact(input)
        XCTAssertFalse(result.text.contains("sk_test_TEST"))
        XCTAssertTrue(result.text.contains("[REDACTED:stripe-key]"))
    }

    func testRedactsAWSKey() {
        let input = "AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE"
        let result = redactor.redact(input)
        XCTAssertFalse(result.text.contains("AKIAIOSFODNN7"))
        XCTAssertTrue(result.text.contains("[REDACTED:aws-key]"))
    }

    func testRedactsGoogleAPIKey() {
        let input = "key=AIzaSyA1234567890abcdefghijklmnopqrstuv"
        let result = redactor.redact(input)
        XCTAssertFalse(result.text.contains("AIzaSy"))
        XCTAssertTrue(result.text.contains("[REDACTED:google-key]"))
    }

    func testRedactsBearerToken() {
        let input = "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.abcdef"
        let result = redactor.redact(input)
        XCTAssertFalse(result.text.contains("eyJhbGci"))
        XCTAssertTrue(result.text.contains("Bearer [REDACTED:token]"))
    }

    func testRedactsAuthorizationHeader() {
        let input = "X-Api-Key: supersecretapikey123456"
        let result = redactor.redact(input)
        XCTAssertFalse(result.text.contains("supersecretapikey"))
        XCTAssertTrue(result.text.contains("[REDACTED]"))
    }

    func testRedactsEnvAssignment() {
        let input = "API_KEY=mysecretapikey123\nother=value"
        let result = redactor.redact(input)
        XCTAssertFalse(result.text.contains("mysecretapikey"))
        XCTAssertTrue(result.text.contains("API_KEY=[REDACTED]"))
    }

    func testRedactsPrivateKeyPath() {
        let input = "ssh -i ~/.ssh/id_rsa user@host"
        let result = redactor.redact(input)
        XCTAssertFalse(result.text.contains("id_rsa"))
        XCTAssertTrue(result.text.contains("[REDACTED:key-file]"))
    }

    func testRedactsMultipleSecrets() {
        let input = """
        ANTHROPIC_API_KEY=sk-ant-api03-ABCDEFghijklmnop1234567890
        OPENAI_API_KEY=sk-XYZABCghijklmnop1234567890ABCDEF
        GITHUB_TOKEN=ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij
        """
        let result = redactor.redact(input)
        XCTAssertGreaterThanOrEqual(result.redactionCount, 3)
        XCTAssertFalse(result.text.contains("sk-ant-"))
        XCTAssertFalse(result.text.contains("sk-XYZ"))
        XCTAssertFalse(result.text.contains("ghp_"))
    }

    func testTruncatesLargeOutput() {
        let smallRedactor = SecretRedactor(maxBytes: 100)
        let input = String(repeating: "a", count: 200)
        let result = smallRedactor.redact(input)
        XCTAssertTrue(result.wasTruncated)
        XCTAssertEqual(result.text.utf8.count, 100)
        XCTAssertTrue(result.displayText.contains("truncated"))
    }

    func testDoesNotTruncateSmallOutput() {
        let input = "small output"
        let result = redactor.redact(input)
        XCTAssertFalse(result.wasTruncated)
        XCTAssertEqual(result.text, input)
    }

    func testPreservesNonSecretContent() {
        let input = "Error: file not found at /path/to/file.txt"
        let result = redactor.redact(input)
        XCTAssertEqual(result.text, input)
        XCTAssertEqual(result.redactionCount, 0)
        XCTAssertFalse(result.wasTruncated)
    }

    func testRedactsOpenAIProjectKey() {
        let input = "key=sk-proj-ABCDEFghijklmnop1234567890ABCDEF"
        let result = redactor.redact(input)
        XCTAssertFalse(result.text.contains("sk-proj-"))
        XCTAssertTrue(result.text.contains("[REDACTED:openai-key]"))
    }

    func testDoesNotRedactCommitSHA() {
        let input = "commit 880ace8484221cfc2e9b5aa6c5c0147251a4103b"
        let result = redactor.redact(input)
        XCTAssertEqual(result.redactionCount, 0)
        XCTAssertTrue(result.text.contains("880ace8484221cfc2e9b5aa6c5c0147251a4103b"))
    }

    func testEmptyInput() {
        let result = redactor.redact("")
        XCTAssertEqual(result.text, "")
        XCTAssertEqual(result.redactionCount, 0)
        XCTAssertFalse(result.wasTruncated)
    }

    func testDisplayTextIncludesTruncationNotice() {
        let smallRedactor = SecretRedactor(maxBytes: 50)
        let input = String(repeating: "x", count: 100)
        let result = smallRedactor.redact(input)
        XCTAssertTrue(result.displayText.contains("[... output truncated"))
        XCTAssertTrue(result.displayText.contains("50 bytes omitted"))
    }
}
