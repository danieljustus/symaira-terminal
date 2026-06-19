import AgentKit
import ControlKit
import Foundation
import TerminalCore
import WorktreeKit

/// Bridges PaneManager to the ControlKit OrchestrationControlProvider protocol,
/// making the running app's orchestration state available over the local control
/// socket (see ADR-002 and docs/design/agent-control-surface.md).
///
/// All methods run on the main actor because PaneManager is @MainActor-isolated.
/// ControlServer dispatches requests to this adapter via the async/await bridge
/// that crosses the main-actor boundary automatically.
///
/// Security guarantees enforced here:
/// - spawn() always starts from EnvironmentSanitizer.sanitizedProcessEnvironment()
///   so spawned agents never inherit provider secrets or agent control flags.
/// - approve/deny verbs are absent from OrchestrationControlProvider by design;
///   this adapter therefore cannot expose them even by mistake.
@MainActor
final class OrchestrationControlAdapter: OrchestrationControlProvider {

    private unowned let paneManager: PaneManager
    /// Tracks when each pane entered awaitingApproval so waitingSince is accurate.
    private var approvalStartTimes: [UUID: Date] = [:]

    init(paneManager: PaneManager) {
        self.paneManager = paneManager
    }

    // MARK: - Status tracking (called by the app when a pane's status changes)

    func noteStatusChange(paneID: UUID, status: AgentStatus) {
        if status == .awaitingApproval, approvalStartTimes[paneID] == nil {
            approvalStartTimes[paneID] = Date()
        } else if status != .awaitingApproval {
            approvalStartTimes.removeValue(forKey: paneID)
        }
    }

    // MARK: - OrchestrationControlProvider

    func snapshot() async throws -> OrchestrationSnapshot {
        let paneSnapshots = paneManager.panes.map(makePaneSnapshot)
        let approvals = makePendingApprovals(from: paneManager.panes)
        let worktreeSnapshots = makeWorktreeSnapshots()

        return OrchestrationSnapshot(
            panes: paneSnapshots,
            currentPaneID: paneManager.currentPane?.paneID,
            pendingApprovals: approvals,
            worktrees: worktreeSnapshots,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        )
    }

    func panes() async throws -> [PaneSnapshot] {
        paneManager.panes.map(makePaneSnapshot)
    }

    func pendingApprovals() async throws -> [ApprovalSummary] {
        makePendingApprovals(from: paneManager.panes)
    }

    func worktrees() async throws -> [WorktreeSnapshot] {
        makeWorktreeSnapshots()
    }

    func spawn(agentID: String, worktreeBranch: String?, workingDirectory: String?) async throws -> UUID {
        guard let agent = AgentCatalog.lookup(id: agentID) else {
            let known = AgentCatalog.all.map(\.id).joined(separator: ", ")
            throw ControlRPCError(
                code: -32000,
                message: "Unknown agent ID '\(agentID)'. Valid agents: \(known)")
        }

        guard let execName = agent.executableNames.first,
              let execPath = AgentCatalog.resolveExecutablePath(named: execName) else {
            throw ControlRPCError(
                code: -32000,
                message: "Agent '\(agentID)' executable '\(agent.executableNames.first ?? "?")' not found in PATH")
        }

        if let cwd = workingDirectory {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: cwd, isDirectory: &isDir),
                  isDir.boolValue else {
                throw ControlRPCError(
                    code: -32602,
                    message: "Working directory does not exist or is not a directory: \(cwd)")
            }
        }

        var config = TerminalSurfaceConfiguration()
        config.environment = EnvironmentSanitizer.sanitizedProcessEnvironment()
        config.executablePath = execPath
        config.arguments = []

        if let cwd = workingDirectory.map(URL.init(fileURLWithPath:)) {
            config.workingDirectory = cwd
        } else if let branch = worktreeBranch,
                  let wt = try? paneManager.worktreeManager?.list().first(where: { $0.branch == branch }) {
            config.workingDirectory = wt.path
        }

        let pane = paneManager.createPane(at: config)
        return pane.paneID
    }

    func focus(paneID: UUID) async throws {
        guard let idx = paneManager.panes.firstIndex(where: { $0.paneID == paneID }) else {
            throw ControlRPCError(code: -32000, message: "Pane not found: \(paneID)")
        }
        paneManager.selectPane(at: idx)
    }

    func blocked() async throws -> UUID? {
        let blocked = paneManager.panes.filter { $0.agentStatus == .awaitingApproval }
        guard let target = blocked.min(by: { a, b in
            let ta = approvalStartTimes[a.paneID] ?? .distantFuture
            let tb = approvalStartTimes[b.paneID] ?? .distantFuture
            return ta < tb
        }) else { return nil }
        paneManager.selectPane(at: paneManager.panes.firstIndex(where: { $0 === target }) ?? 0)
        return target.paneID
    }

    func readScrollback(paneID: UUID?, lines: Int) async throws -> ScrollbackResult {
        guard let pid = paneID,
              let pane = paneManager.panes.first(where: { $0.paneID == pid }) else {
            return ScrollbackResult(paneID: paneID, lines: [])
        }
        let text = pane.scrollbackBuffer.currentText ?? ""
        let allLines = text.components(separatedBy: "\n")
        return ScrollbackResult(paneID: pid, lines: Array(allLines.suffix(lines)))
    }

    func requestOpenTab(command: String) async throws -> TabRequestResult {
        let requestID = UUID()
        var config = TerminalSurfaceConfiguration()
        config.environment = EnvironmentSanitizer.sanitizedProcessEnvironment()
        config.command = command
        paneManager.createPane(at: config)
        return TabRequestResult(requestID: requestID, status: "opened")
    }

    // MARK: - Helpers

    private func makePaneSnapshot(_ pane: TerminalPane) -> PaneSnapshot {
        let cwd = pane.configuration.workingDirectory?.lastPathComponent
        let title = cwd ?? (pane.configuration.executablePath ?? "shell")
        return PaneSnapshot(
            id: pane.paneID,
            title: title,
            workingDirectory: pane.configuration.workingDirectory?.path,
            agentStatus: pane.agentStatus,
            agentStatusSource: pane.statusEngine.currentSource,
            agentDetail: pane.statusEngine.detail,
            isCurrent: pane === paneManager.currentPane,
            isZoomed: pane === paneManager.zoomedPane
        )
    }

    private func makePendingApprovals(from panes: [TerminalPane]) -> [ApprovalSummary] {
        panes
            .filter { $0.agentStatus == .awaitingApproval }
            .map { pane in
                ApprovalSummary(
                    paneID: pane.paneID,
                    promptSummary: pane.statusEngine.detail ?? "Awaiting approval",
                    waitingSince: approvalStartTimes[pane.paneID] ?? Date()
                )
            }
    }

    private func makeWorktreeSnapshots() -> [WorktreeSnapshot] {
        guard let wm = paneManager.worktreeManager,
              let worktrees = try? wm.list() else { return [] }
        return worktrees.map { wt in
            // Find a pane whose working directory matches this worktree path.
            let linked = paneManager.panes.first {
                $0.configuration.workingDirectory == wt.path
            }
            return WorktreeSnapshot(
                branch: wt.branch,
                path: wt.path.path,
                linkedPaneID: linked?.paneID
            )
        }
    }
}
