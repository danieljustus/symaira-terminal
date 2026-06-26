import Foundation

/// Engine-neutral abstraction over the terminal rendering/emulation backend.
///
/// `GhosttyBridge` provides the production implementation on top of GhosttyKit;
/// the rest of the app must only ever talk to these protocols so the engine
/// stays swappable (libghostty's C API is not yet stable — see ADR-001).
@MainActor
public protocol TerminalEngine: AnyObject {
    /// Human-readable engine identification for diagnostics ("ghostty x.y.z").
    var engineDescription: String { get }

    /// Creates a new surface running the given command in the given directory.
    func makeSurface(configuration: TerminalSurfaceConfiguration) throws -> any TerminalSurface
}

/// One terminal pane: a live emulation grid bound to a child process.
///
/// View-hosting is intentionally excluded from this protocol. `TerminalCore`
/// must remain free of AppKit types (see AGENTS.md). Concrete engine
/// implementations (e.g. `GhosttySurfaceController` in `GhosttyBridge`) expose
/// their `NSView` directly; the App layer downcasts to access it.
@MainActor
public protocol TerminalSurface: AnyObject {
    /// Tap on the raw PTY output stream (called on an arbitrary queue) so the
    /// host can run `OSCStreamParser` for agent awareness without interfering
    /// with the engine's own VT processing.
    var outputTap: (@Sendable (_ bytes: [UInt8]) -> Void)? { get set }

    /// Sends text to the child process as if typed.
    func sendText(_ text: String)

    /// Terminates the child process and releases engine resources.
    func close()

    /// The process ID of the child process (typically the shell).
    var pid: pid_t { get }
}

public struct TerminalSurfaceConfiguration: Sendable {
    /// Command to execute; `nil` runs the user's configured shell.
    public var command: String?
    /// Shell executable path (e.g. "/bin/zsh"). `nil` uses the system default.
    public var executablePath: String?
    /// Arguments passed to the shell (e.g. ["-l"] for login shell).
    public var arguments: [String]
    public var workingDirectory: URL?
    /// Environment for the child. Callers should start from
    /// `EnvironmentSanitizer.sanitizedProcessEnvironment()` and add what the
    /// workspace profile explicitly routes in.
    public var environment: [String: String]
    /// Maximum scrollback lines for the in-memory buffer.
    public var scrollbackLines: Int

    public init(
        command: String? = nil,
        executablePath: String? = nil,
        arguments: [String] = ["-l"],
        workingDirectory: URL? = nil,
        environment: [String: String] = EnvironmentSanitizer.sanitizedProcessEnvironment(),
        scrollbackLines: Int = 10_000
    ) {
        self.command = command
        self.executablePath = executablePath
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.scrollbackLines = scrollbackLines
    }
}
