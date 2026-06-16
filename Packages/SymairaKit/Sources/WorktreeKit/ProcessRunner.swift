import Darwin
import Foundation

/// Thread-safe box for collecting output from a concurrent pipe drain.
final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = Data()
    func set(_ d: Data) { lock.lock(); _value = d; lock.unlock() }
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
        let flags = fcntl(fd, F_GETFL)
        guard flags != -1 else { return Data() }
        
        fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 65536)
        
        while true {
            let n = buf.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            
            if n > 0 {
                data.append(contentsOf: buf[0..<n])
            } else if n == -1 {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    usleep(1000)
                    continue
                }
                break
            } else {
                break
            }
        }
        
        fcntl(fd, F_SETFL, flags)
        return data
    }
}
