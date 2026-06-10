#if canImport(AppKit)
import AppKit
#endif
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
@MainActor
public protocol TerminalSurface: AnyObject {
    #if canImport(AppKit)
    /// The view to host in the pane hierarchy. The engine owns rendering.
    var view: NSView { get }
    #endif

    /// Tap on the raw PTY output stream (called on an arbitrary queue) so the
    /// host can run `OSCStreamParser` for agent awareness without interfering
    /// with the engine's own VT processing.
    var outputTap: (@Sendable (_ bytes: [UInt8]) -> Void)? { get set }

    /// Sends text to the child process as if typed.
    func sendText(_ text: String)

    /// Terminates the child process and releases engine resources.
    func close()
}

public struct TerminalSurfaceConfiguration: Sendable {
    /// Command to execute; `nil` runs the user's default shell as login shell.
    public var command: String?
    public var workingDirectory: URL?
    /// Environment for the child. Callers should start from
    /// `EnvironmentSanitizer.sanitizedProcessEnvironment()` and add what the
    /// workspace profile explicitly routes in.
    public var environment: [String: String]

    public init(
        command: String? = nil,
        workingDirectory: URL? = nil,
        environment: [String: String] = EnvironmentSanitizer.sanitizedProcessEnvironment()
    ) {
        self.command = command
        self.workingDirectory = workingDirectory
        self.environment = environment
    }
}
