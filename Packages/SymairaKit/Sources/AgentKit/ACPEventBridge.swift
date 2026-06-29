import Foundation
import os.log

/// Bridges ACPClient events to AgentStatusEngine and stores pending permission requests.
///
/// Usage:
/// ```swift
/// let bridge = ACPEventBridge()
/// acpClient.onEvent { event in bridge.handleEvent(event, for: paneID) }
/// // Later, when user approves/denies:
/// bridge.respond(to: permissionID, allowed: true)
/// ```
public final class ACPEventBridge: @unchecked Sendable {
    private let lock = NSLock()
    private var engines: [UUID: AgentStatusEngine] = [:]
    private var pendingPermissions: [Int: PendingPermission] = [:]
    private var responseHandlers: [Int: (Bool) -> Void] = [:]

    public struct PendingPermission: Sendable {
        public let paneID: UUID
        public let toolName: String
        public let description: String?
        public let receivedAt: Date
    }

    public init() {}

    public func handleEvent(_ event: ACPEvent, for paneID: UUID) {
        switch event {
        case .statusChange(let status):
            let observation = StatusObservation(
                mapACPStatus(status),
                source: .acp,
                detail: status)
            lock.lock()
            var engine = engines[paneID] ?? AgentStatusEngine()
            engine.apply(observation)
            engines[paneID] = engine
            lock.unlock()

        case .permissionRequest(let id, let toolName, let description):
            let pending = PendingPermission(
                paneID: paneID,
                toolName: toolName,
                description: description,
                receivedAt: Date())
            lock.lock()
            pendingPermissions[id] = pending
            var engine = engines[paneID] ?? AgentStatusEngine()
            engine.apply(StatusObservation(.awaitingApproval, source: .acp, detail: toolName))
            engines[paneID] = engine
            lock.unlock()

        case .error(let code, let message):
            let observation = StatusObservation(
                .error,
                source: .acp,
                detail: "ACP error \(code): \(message)")
            lock.lock()
            var engine = engines[paneID] ?? AgentStatusEngine()
            engine.apply(observation)
            engines[paneID] = engine
            lock.unlock()

        case .toolCall, .toolResult, .permissionResponse:
            break
        }
    }

    public func registerResponseHandler(for permissionID: Int, handler: @escaping (Bool) -> Void) {
        lock.lock()
        responseHandlers[permissionID] = handler
        lock.unlock()
    }

    public func respond(to permissionID: Int, allowed: Bool) {
        lock.lock()
        let handler = responseHandlers.removeValue(forKey: permissionID)
        let pending = pendingPermissions.removeValue(forKey: permissionID)
        lock.unlock()

        handler?(allowed)

        if let pending {
            let observation = StatusObservation(
                .running,
                source: .acp,
                detail: allowed ? "approved \(pending.toolName)" : "denied \(pending.toolName)")
            lock.lock()
            var engine = engines[pending.paneID] ?? AgentStatusEngine()
            engine.apply(observation)
            engines[pending.paneID] = engine
            lock.unlock()
        }
    }

    public func status(for paneID: UUID) -> AgentStatusEngine {
        lock.lock()
        defer { lock.unlock() }
        return engines[paneID] ?? AgentStatusEngine()
    }

    public func pendingPermissionsForPane(_ paneID: UUID) -> [PendingPermission] {
        lock.lock()
        defer { lock.unlock() }
        return pendingPermissions.values.filter { $0.paneID == paneID }
    }

    private func mapACPStatus(_ status: String) -> AgentStatus {
        switch status.lowercased() {
        case "running", "active", "working": return .running
        case "idle", "waiting", "paused": return .idle
        case "error", "failed": return .error
        case "done", "completed", "finished": return .done
        default: return .running
        }
    }
}
