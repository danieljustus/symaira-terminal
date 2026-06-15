import Foundation
import Testing
@testable import WorktreeKit

@Suite struct ProcessRunnerTests {
    @Test func runReturnsStdoutAndStderr() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf 'out'; printf 'err' >&2"]
        let result = try ProcessRunner.run(process)
        #expect(String(data: result.stdout, encoding: .utf8) == "out")
        #expect(String(data: result.stderr, encoding: .utf8) == "err")
        #expect(result.exitCode == 0)
    }

    @Test func runTimeoutKillsProcessAndReturnsNil() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["10"]
        let result = try ProcessRunner.run(process, timeout: 0.2)
        #expect(result == nil)
        #expect(!process.isRunning)
    }

    @Test func runNoTimeoutReturnsResult() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/echo")
        process.arguments = ["hello"]
        let result = try ProcessRunner.run(process)
        #expect(String(data: result.stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "hello")
        #expect(result.exitCode == 0)
    }

    @Test func runConcurrentDrainDoesNotDeadlock() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "yes x | head -c 200000; yes y | head -c 200000 1>&2"]
        let result = try ProcessRunner.run(process)
        #expect(result.stdout.count == 200000)
        #expect(result.stderr.count == 200000)
    }
}
