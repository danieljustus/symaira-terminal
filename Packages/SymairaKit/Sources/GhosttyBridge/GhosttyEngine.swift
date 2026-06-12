import AppKit
import Foundation
import GhosttyTerminal
import TerminalCore

/// Production `TerminalEngine` backed by GhosttyKit (libghostty) through the
/// `GhosttyTerminal` Swift wrapper. This target is the ONLY place allowed to
/// import GhosttyKit/GhosttyTerminal (ADR-001).
@MainActor
public final class GhosttyEngine: TerminalEngine {
    /// Shared ghostty app/config controller. Picks up the user's existing
    /// Ghostty configuration (themes, fonts, keybindings) when present.
    private let controller: GhosttyTerminal.TerminalController

    public init() {
        let userConfigPath = ("~/.config/ghostty/config" as NSString).expandingTildeInPath
        if let contents = try? String(contentsOfFile: userConfigPath, encoding: .utf8) {
            let prepared = GhosttyUserConfig.prepare(contents: contents)
            if let theme = prepared.theme {
                controller = GhosttyTerminal.TerminalController(
                    configSource: .generated(prepared.contents),
                    theme: theme
                )
            } else {
                controller = GhosttyTerminal.TerminalController(
                    configSource: .generated(prepared.contents)
                )
            }
            let issues = GhosttyUserConfig.diagnostics(for: prepared.contents)
            if !issues.isEmpty {
                NSLog(
                    "symaira: ghostty config %@ has issues, engine ignores it and uses defaults: %@",
                    userConfigPath, issues.joined(separator: " | ")
                )
            }
        } else {
            controller = GhosttyTerminal.TerminalController()
        }
    }

    public var engineDescription: String {
        "libghostty (libghostty-spm \(GhosttyEngineInfo.pinnedPackageVersion))"
    }

    public func makeSurface(
        configuration: TerminalSurfaceConfiguration
    ) throws -> any TerminalCore.TerminalSurface {
        try GhosttySurfaceController(configuration: configuration, controller: controller)
    }
}

/// One pane: GhosttyKit renders, while the app owns the PTY. Bytes flow
///
///     PTY (zsh/agent) → InMemoryTerminalSession.receive → ghostty VT/Metal
///     ghostty input   → session write callback          → PTY master
///
/// The host-managed PTY is what enables the OSC tap (agent awareness) and
/// environment sanitation at spawn time.
@MainActor
public final class GhosttySurfaceController: TerminalCore.TerminalSurface {
    public let terminalView: GhosttyTerminal.TerminalView
    public var view: NSView { terminalView }

    private let pty: PTYSession
    private let session: InMemoryTerminalSession
    private let tap = TapBox()

    public var outputTap: (@Sendable ([UInt8]) -> Void)? {
        get { tap.handler }
        set { tap.handler = newValue }
    }

    init(
        configuration: TerminalSurfaceConfiguration,
        controller: GhosttyTerminal.TerminalController
    ) throws {
        var ptyConfiguration = PTYSession.Configuration(
            environment: configuration.environment,
            workingDirectory: configuration.workingDirectory?.path
        )
        if let command = configuration.command {
            ptyConfiguration.executablePath = "/bin/zsh"
            ptyConfiguration.arguments = ["-lc", command]
        }
        let pty = PTYSession(configuration: ptyConfiguration)
        self.pty = pty

        session = InMemoryTerminalSession(
            write: { [weak pty] data in
                pty?.write(data)
            },
            resize: { [weak pty] viewport in
                pty?.resize(
                    columns: UInt16(clamping: viewport.columns),
                    rows: UInt16(clamping: viewport.rows),
                    widthPixels: UInt16(clamping: viewport.widthPixels),
                    heightPixels: UInt16(clamping: viewport.heightPixels)
                )
            }
        )

        terminalView = GhosttyTerminal.TerminalView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        terminalView.controller = controller
        terminalView.configuration = TerminalSurfaceOptions(
            backend: .inMemory(session),
            workingDirectory: configuration.workingDirectory?.path
        )

        let session = self.session
        let tap = self.tap
        pty.onOutput = { data in
            session.receive(data)
            tap.handler?(Array(data))
        }
        pty.onExit = { exitCode in
            session.finish(exitCode: UInt32(bitPattern: exitCode), runtimeMilliseconds: 0)
        }
        try pty.start()
    }

    public func sendText(_ text: String) {
        pty.write(Data(text.utf8))
    }

    /// Plain-text snapshot of the visible grid. Used by "send output to agent"
    /// features and by the M0 smoke check.
    public func readViewportText() -> String? {
        session.readViewportText()
    }

    public func close() {
        pty.terminate()
    }
}

/// Cross-thread handoff for the output tap: set on the main actor, read on the
/// PTY queue.
private final class TapBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _handler: (@Sendable ([UInt8]) -> Void)?

    var handler: (@Sendable ([UInt8]) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _handler }
        set { lock.lock(); defer { lock.unlock() }; _handler = newValue }
    }
}
