import Darwin
import Foundation

public enum PTYError: Error {
    case spawnFailed(errno: Int32)
    case notRunning
}

/// Host-managed pseudo-terminal running a child process (typically the user's
/// shell). The app owns the PTY rather than delegating it to the engine so it
/// can tap the byte stream for agent awareness, sanitize the child
/// environment, and persist sessions independently of the renderer.
///
/// Thread-safety: all I/O is confined to an internal serial queue; callbacks
/// (`onOutput`, `onExit`) fire on that queue — hop to the main actor yourself.
public final class PTYSession: @unchecked Sendable {
    public struct Configuration: Sendable {
        public var executablePath: String
        public var arguments: [String]
        public var environment: [String: String]
        public var workingDirectory: String?
        public var initialColumns: UInt16
        public var initialRows: UInt16

        public init(
            executablePath: String = "/bin/zsh",
            arguments: [String] = ["-l"],
            environment: [String: String] = EnvironmentSanitizer.sanitizedProcessEnvironment(),
            workingDirectory: String? = nil,
            initialColumns: UInt16 = 80,
            initialRows: UInt16 = 24
        ) {
            self.executablePath = executablePath
            self.arguments = arguments
            self.environment = environment
            self.workingDirectory = workingDirectory
            self.initialColumns = initialColumns
            self.initialRows = initialRows
        }
    }

    public let configuration: Configuration
    public var onOutput: (@Sendable (Data) -> Void)?
    public var onExit: (@Sendable (Int32) -> Void)?

    private let queue = DispatchQueue(label: "com.symaira.terminal.pty")
    private var masterFD: Int32 = -1
    private var childPID: pid_t = -1
    private var readSource: DispatchSourceRead?
    private var exitSource: DispatchSourceProcess?

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    deinit {
        terminate()
    }

    public func start() throws {
        var window = winsize(
            ws_row: configuration.initialRows,
            ws_col: configuration.initialColumns,
            ws_xpixel: 0,
            ws_ypixel: 0
        )

        // Allocate exec arguments before fork: only async-signal-safe calls
        // are allowed in the child between fork and exec.
        var environment = configuration.environment
        environment["TERM"] = environment["TERM"] ?? "xterm-256color"
        environment["COLORTERM"] = environment["COLORTERM"] ?? "truecolor"
        let argv0 = (configuration.executablePath as NSString).lastPathComponent
        var argv: [UnsafeMutablePointer<CChar>?] = ([argv0] + configuration.arguments).map { strdup($0) }
        argv.append(nil)
        var envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0)=\($1)") }
        envp.append(nil)
        let executable = strdup(configuration.executablePath)
        let cwd = configuration.workingDirectory.map { strdup($0) }
        defer {
            (argv + envp + [executable, cwd ?? nil]).forEach { free($0) }
        }

        var master: Int32 = -1
        let pid = forkpty(&master, nil, nil, &window)
        if pid < 0 {
            throw PTYError.spawnFailed(errno: errno)
        }
        if pid == 0 {
            // Child: async-signal-safe territory only.
            if let cwd { _ = chdir(cwd) }
            _ = execve(executable, argv, envp)
            _exit(127)
        }

        masterFD = master
        childPID = pid

        let readSource = DispatchSource.makeReadSource(fileDescriptor: master, queue: queue)
        readSource.setEventHandler { [weak self] in
            guard let self, self.masterFD >= 0 else { return }
            var buffer = [UInt8](repeating: 0, count: 65536)
            let count = read(self.masterFD, &buffer, buffer.count)
            if count > 0 {
                self.onOutput?(Data(buffer[0..<count]))
            } else {
                self.readSource?.cancel()
            }
        }
        readSource.resume()
        self.readSource = readSource

        let exitSource = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
        exitSource.setEventHandler { [weak self] in
            guard let self else { return }
            var status: Int32 = 0
            waitpid(pid, &status, 0)
            let exitCode: Int32 = (status & 0x7F) == 0 ? (status >> 8) & 0xFF : 128 + (status & 0x7F)
            self.cleanup()
            self.onExit?(exitCode)
        }
        exitSource.resume()
        self.exitSource = exitSource
    }

    public var isRunning: Bool { childPID > 0 }

    public func write(_ data: Data) {
        queue.async { [weak self] in
            guard let self, self.masterFD >= 0 else { return }
            data.withUnsafeBytes { raw in
                var offset = 0
                while offset < raw.count {
                    let written = Darwin.write(self.masterFD, raw.baseAddress! + offset, raw.count - offset)
                    if written <= 0 { break }
                    offset += written
                }
            }
        }
    }

    public func resize(columns: UInt16, rows: UInt16, widthPixels: UInt16 = 0, heightPixels: UInt16 = 0) {
        queue.async { [weak self] in
            guard let self, self.masterFD >= 0 else { return }
            var window = winsize(
                ws_row: rows, ws_col: columns,
                ws_xpixel: widthPixels, ws_ypixel: heightPixels
            )
            _ = ioctl(self.masterFD, TIOCSWINSZ, &window)
        }
    }

    public func terminate() {
        if childPID > 0 {
            kill(childPID, SIGHUP)
        }
    }

    private func cleanup() {
        readSource?.cancel()
        readSource = nil
        exitSource?.cancel()
        exitSource = nil
        if masterFD >= 0 {
            close(masterFD)
            masterFD = -1
        }
        childPID = -1
    }
}
