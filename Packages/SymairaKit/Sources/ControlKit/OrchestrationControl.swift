import AgentKit
import Foundation

/// Protocol the App implements to handle control requests on the main actor.
/// ControlKit defines the contract; the App provides the concrete implementation
/// by reading PaneManager and WorktreeManager state.
public protocol OrchestrationControlProvider: Sendable {
    /// Full read-only snapshot of the current orchestration state.
    func snapshot() async throws -> OrchestrationSnapshot

    /// All current terminal panes.
    func panes() async throws -> [PaneSnapshot]

    /// Pending agent approval requests (observe-only — approve/deny is GUI-only).
    func pendingApprovals() async throws -> [ApprovalSummary]

    /// Active worktrees.
    func worktrees() async throws -> [WorktreeSnapshot]

    /// Open a new pane running the named agent, optionally in a worktree branch.
    func spawn(agentID: String, worktreeBranch: String?, workingDirectory: String?) async throws -> UUID

    /// Make the given pane current.
    func focus(paneID: UUID) async throws

    /// Report (and optionally focus) the pane that has been awaiting approval longest.
    /// Returns nil when no pane is blocked.
    func blocked() async throws -> UUID?

    /// Read the last N lines from a pane's scrollback buffer.
    func readScrollback(paneID: UUID?, lines: Int) async throws -> ScrollbackResult

    /// Request opening a new terminal tab with a shell command.
    /// The request routes through the approval queue — the command is never
    /// executed without explicit user confirmation.
    func requestOpenTab(command: String) async throws -> TabRequestResult
}

// MARK: - Scrollback / Tab result types

public struct ScrollbackResult: Codable, Sendable {
    public var paneID: UUID?
    public var lines: [String]

    public init(paneID: UUID? = nil, lines: [String] = []) {
        self.paneID = paneID
        self.lines = lines
    }
}

public struct TabRequestResult: Codable, Sendable {
    public var requestID: UUID
    public var status: String

    public init(requestID: UUID = UUID(), status: String = "pending_approval") {
        self.requestID = requestID
        self.status = status
    }
}

// MARK: - Snapshot DTOs

/// Top-level read-only view of the running app's orchestration state.
public struct OrchestrationSnapshot: Codable, Sendable {
    public var panes: [PaneSnapshot]
    public var currentPaneID: UUID?
    public var pendingApprovals: [ApprovalSummary]
    public var worktrees: [WorktreeSnapshot]
    public var appVersion: String
    public var capturedAt: Date

    public init(
        panes: [PaneSnapshot] = [],
        currentPaneID: UUID? = nil,
        pendingApprovals: [ApprovalSummary] = [],
        worktrees: [WorktreeSnapshot] = [],
        appVersion: String = "",
        capturedAt: Date = Date()
    ) {
        self.panes = panes
        self.currentPaneID = currentPaneID
        self.pendingApprovals = pendingApprovals
        self.worktrees = worktrees
        self.appVersion = appVersion
        self.capturedAt = capturedAt
    }
}

public struct PaneSnapshot: Codable, Sendable {
    public var id: UUID
    public var title: String
    public var workingDirectory: String?
    public var agentStatus: AgentStatus
    public var agentStatusSource: StatusSource
    public var agentDetail: String?
    public var isCurrent: Bool
    public var isZoomed: Bool
    public var worktreeBranch: String?

    public init(
        id: UUID = UUID(),
        title: String,
        workingDirectory: String? = nil,
        agentStatus: AgentStatus = .idle,
        agentStatusSource: StatusSource = .heuristic,
        agentDetail: String? = nil,
        isCurrent: Bool = false,
        isZoomed: Bool = false,
        worktreeBranch: String? = nil
    ) {
        self.id = id
        self.title = title
        self.workingDirectory = workingDirectory
        self.agentStatus = agentStatus
        self.agentStatusSource = agentStatusSource
        self.agentDetail = agentDetail
        self.isCurrent = isCurrent
        self.isZoomed = isZoomed
        self.worktreeBranch = worktreeBranch
    }
}

public struct WorktreeSnapshot: Codable, Sendable {
    public var branch: String
    public var path: String
    public var hasUncommittedChanges: Bool
    public var linkedPaneID: UUID?

    public init(
        branch: String,
        path: String,
        hasUncommittedChanges: Bool = false,
        linkedPaneID: UUID? = nil
    ) {
        self.branch = branch
        self.path = path
        self.hasUncommittedChanges = hasUncommittedChanges
        self.linkedPaneID = linkedPaneID
    }
}

/// A pending agent approval — observe-only. No approve/deny field exists by design:
/// approvals are handled exclusively through the GUI by the human in the loop.
public struct ApprovalSummary: Codable, Sendable {
    public var paneID: UUID
    public var agentName: String?
    public var promptSummary: String
    public var waitingSince: Date

    public init(
        paneID: UUID,
        agentName: String? = nil,
        promptSummary: String,
        waitingSince: Date = Date()
    ) {
        self.paneID = paneID
        self.agentName = agentName
        self.promptSummary = promptSummary
        self.waitingSince = waitingSince
    }
}
