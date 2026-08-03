import Darwin
import Foundation

/// Thread-safe box for collecting output from a concurrent pipe drain.
final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = Data()
    func set(_ d: Data) { lock.lock(); _value = d; lock.unlock() }
    func append(_ d: Data) { lock.lock(); _value.append(d); lock.unlock() }
    var value: Data { lock.lock(); defer { lock.unlock() }; return _value }
}

/// Sendable flag set from a timeout dispatch work item.
private final class TimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _fired = false
    func fire() { lock.lock(); _fired = true; lock.unlock() }
    var hasFired: Bool { lock.lock(); defer { lock.unlock() }; return _fired }
}

/// Runs subprocesses with concurrent stdout/stderr drain and an optional timeout.
///
/// Sequential drain (reading one stream to EOF before the other) deadlocks whenever
/// the unread stream fills its ~64 KB kernel pipe buffer. The concurrent drain avoids
/// this by reading both streams in parallel before waiting for exit.
public struct ProcessRunner: Sendable {
    public struct Result: Sendable {
        public let stdout: Data
        public let stderr: Data
        public let exitCode: Int32
    }

    /// Run `process`, draining both streams concurrently. Non-optional overload
    /// for callers that do not need a timeout (e.g. WorktreeManager git plumbing).
    @discardableResult
    public static func run(_ process: Process) throws -> Result {
        try runImpl(process, timeout: nil)!
    }

    /// Run `process` with a wall-clock timeout. Returns `nil` if the process is
    /// terminated after `timeout` seconds; otherwise returns the full result.
    public static func run(_ process: Process, timeout: TimeInterval) throws -> Result? {
        try runImpl(process, timeout: timeout)
    }

    /// Convenience: build and run a process, returning trimmed stdout or nil.
    /// Runs blocking work on a background queue so the caller's actor is freed.
    public static func runReturningStdout(
        executable: String,
        arguments: [String],
        directory: URL? = nil,
        timeout: TimeInterval = 15
    ) async -> String? {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.currentDirectoryURL = directory
                guard let result = try? ProcessRunner.run(process, timeout: timeout),
                      result.exitCode == 0 else {
                    cont.resume(returning: nil)
                    return
                }
                let text = String(data: result.stdout, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                cont.resume(returning: text)
            }
        }
    }

    // MARK: - Internal

    private static func runImpl(_ process: Process, timeout: TimeInterval?) throws -> Result? {
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError  = errPipe
        try process.run()

        // Set up optional timeout using the process PID (Int32, Sendable) to avoid
        // capturing the non-Sendable Process across a concurrency boundary.
        let flag = TimeoutFlag()
        var timeoutItem: DispatchWorkItem?
        if let t = timeout {
            let pid = process.processIdentifier
            let item = DispatchWorkItem {
                if kill(pid, 0) == 0 { kill(pid, SIGTERM) }
                flag.fire()
            }
            timeoutItem = item
            DispatchQueue.global().asyncAfter(deadline: .now() + t, execute: item)
        }

        let outFD = outPipe.fileHandleForReading.fileDescriptor
        let errFD = errPipe.fileHandleForReading.fileDescriptor
        let outBox = DataBox(), errBox = DataBox()
        let group = DispatchGroup()
        let queue = DispatchQueue.global(qos: .userInitiated)
        queue.async(group: group) { outBox.set(drain(outFD)) }
        queue.async(group: group) { errBox.set(drain(errFD)) }
        group.wait()
        process.waitUntilExit()
        timeoutItem?.cancel()

        guard !flag.hasFired else { return nil }
        return Result(stdout: outBox.value, stderr: errBox.value, exitCode: process.terminationStatus)
    }

    static func drain(_ fd: Int32) -> Data {
        // Do the blocking read directly on the drain worker. The previous
        // DispatchSource implementation blocked a global-queue worker waiting
        // for a handler scheduled on that same queue; concurrent Swift Testing
        // runs could exhaust the pool and leave the test process hanging.
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)

        while true {
            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                read(fd, rawBuffer.baseAddress, rawBuffer.count)
            }

            if count > 0 {
                data.append(contentsOf: buffer.prefix(Int(count)))
            } else if count == 0 {
                break
            } else if errno == EINTR {
                continue
            } else {
                break
            }
        }

        return data
    }
}
