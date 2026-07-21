import ControlKit
import Foundation
import MCPKit
import UserNotifications

/// Manages the lifecycle of the control server, MCP server, and
/// sleep-prevention activation — the "background services" that
/// AppDelegate formerly owned directly.
///
/// Extracted from:
/// - `startControlSurface(paneManager:)` (AppDelegate lines 319-348)
/// - server stop calls in `applicationWillTerminate` (lines 296-298)
/// - `notify(title:body:)` helper (lines 350-357)
@MainActor
final class BackgroundServicesController {
    private let controlAdapter: OrchestrationControlAdapter
    private(set) var controlServer: ControlServer?
    private(set) var mcpServer: MCPServer?

    init(paneManager: PaneManager) {
        self.controlAdapter = OrchestrationControlAdapter(paneManager: paneManager)
    }

    // MARK: - Lifecycle

    /// Start both the control server and MCP server, logging results and
    /// posting user notifications on failure.
    func start() {
        startControlServer()
        startMCPServer()
    }

    /// Stop both servers. Safe to call even if `start()` was never called.
    func stop() async {
        await controlServer?.stop()
        await mcpServer?.stop()
    }

    // MARK: - Private

    private func startControlServer() {
        let server = ControlServer()
        self.controlServer = server
        Task {
            do {
                try await server.start(provider: controlAdapter)
                let path = await server.socketPath
                NSLog("symaira: control server listening at %@", path)
            } catch {
                NSLog(
                    "symaira: failed to start control server: %@",
                    String(describing: error)
                )
                notify(
                    title: "Control Server Failed",
                    body: "Could not start the control server: \(error.localizedDescription)"
                )
            }
        }
    }

    private func startMCPServer() {
        let server = MCPServer()
        self.mcpServer = server
        Task {
            do {
                try await server.start(provider: controlAdapter)
                let path = await server.socketPath
                NSLog("symaira: mcp server listening at %@", path)
            } catch {
                NSLog(
                    "symaira: failed to start mcp server: %@",
                    String(describing: error)
                )
                notify(
                    title: "MCP Server Failed",
                    body: "Could not start the MCP server: \(error.localizedDescription)"
                )
            }
        }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
