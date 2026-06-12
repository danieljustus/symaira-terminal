import XCTest
@testable import AgentKit
import TerminalCore

final class ACPConfigurationTests: XCTestCase {
    func testDefaultConfigurationUsesSanitizedEnvironment() {
        let executable = URL(fileURLWithPath: "/usr/bin/test")
        let config = ACPConfiguration(executable: executable)

        XCTAssertFalse(config.environment.contains { $0.key == "CLAUDECODE" })
        XCTAssertFalse(config.environment.contains { $0.key == "GOOGLE_API_KEY" })
        XCTAssertFalse(config.environment.contains { $0.key.hasPrefix("ANTHROPIC_") })
        XCTAssertFalse(config.environment.contains { $0.key.hasPrefix("OPENAI_") })
    }

    func testConfigurationWithProviderKey() {
        let executable = URL(fileURLWithPath: "/usr/bin/gemini")
        let config = ACPConfiguration.withProviderKey(
            executable: executable,
            arguments: ["--acp"],
            keyName: "GOOGLE_API_KEY",
            keyValue: "test-key-12345",
            workingDirectory: URL(fileURLWithPath: "/tmp/work")
        )

        XCTAssertEqual(config.executable, executable)
        XCTAssertEqual(config.arguments, ["--acp"])
        XCTAssertEqual(config.environment["GOOGLE_API_KEY"], "test-key-12345")
        XCTAssertEqual(config.workingDirectory, URL(fileURLWithPath: "/tmp/work"))
    }

    func testExplicitEnvironmentIsUsedAsProvided() {
        var explicitEnv: [String: String] = ["CUSTOM_VAR": "value"]

        let executable = URL(fileURLWithPath: "/usr/bin/test")
        let config = ACPConfiguration(executable: executable, environment: explicitEnv)

        XCTAssertEqual(config.environment["CUSTOM_VAR"], "value")
    }

    func testWithProviderKeyStripsInheritedSecrets() {
        let executable = URL(fileURLWithPath: "/usr/bin/gemini")
        let config = ACPConfiguration.withProviderKey(
            executable: executable,
            keyName: "GOOGLE_API_KEY",
            keyValue: "test-key"
        )

        XCTAssertFalse(config.environment.contains { $0.key == "CLAUDECODE" })
        XCTAssertFalse(config.environment.contains { $0.key.hasPrefix("ANTHROPIC_") })
        XCTAssertEqual(config.environment["GOOGLE_API_KEY"], "test-key")
    }

    func testConfigurationPreservesExplicitKeys() {
        let executable = URL(fileURLWithPath: "/usr/bin/test")
        var env = EnvironmentSanitizer.sanitizedProcessEnvironment()
        env["GOOGLE_API_KEY"] = "explicit-key"

        let config = ACPConfiguration(executable: executable, environment: env)

        XCTAssertEqual(config.environment["GOOGLE_API_KEY"], "explicit-key")
    }

    func testConfigurationWithWorkingDirectory() {
        let executable = URL(fileURLWithPath: "/usr/bin/test")
        let workDir = URL(fileURLWithPath: "/tmp/workspace")
        let config = ACPConfiguration(executable: executable, workingDirectory: workDir)

        XCTAssertEqual(config.workingDirectory, workDir)
    }

    func testConfigurationWithoutWorkingDirectory() {
        let executable = URL(fileURLWithPath: "/usr/bin/test")
        let config = ACPConfiguration(executable: executable)

        XCTAssertNil(config.workingDirectory)
    }
}
