import AgentKit
import ControlKit
import Foundation
import Testing

@Suite("OrchestrationSnapshot Codable roundtrip")
struct OrchestrationSnapshotTests {

    let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    @Test func paneSnapshotRoundtrip() throws {
        let id = UUID()
        let original = PaneSnapshot(
            id: id,
            title: "claude",
            workingDirectory: "/tmp/work",
            agentStatus: .awaitingApproval,
            agentStatusSource: .acp,
            agentDetail: "awaiting tool use",
            isCurrent: true,
            isZoomed: false,
            worktreeBranch: "symaira/task-abc"
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(PaneSnapshot.self, from: data)
        #expect(decoded == original)
        #expect(decoded.agentStatus == .awaitingApproval)
        #expect(decoded.agentStatusSource == .acp)
        #expect(decoded.worktreeBranch == "symaira/task-abc")
    }

    @Test func worktreeSnapshotRoundtrip() throws {
        let paneID = UUID()
        let original = WorktreeSnapshot(
            branch: "symaira/task-xyz",
            path: "/tmp/worktrees/xyz",
            hasUncommittedChanges: true,
            linkedPaneID: paneID
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(WorktreeSnapshot.self, from: data)
        #expect(decoded == original)
        #expect(decoded.linkedPaneID == paneID)
    }

    @Test func approvalSummaryRoundtrip() throws {
        let paneID = UUID()
        let waitingSince = Date(timeIntervalSince1970: 1_700_000_000)
        let original = ApprovalSummary(
            paneID: paneID,
            agentName: "claude-code",
            promptSummary: "Bash: rm -rf /tmp/test",
            waitingSince: waitingSince
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ApprovalSummary.self, from: data)
        #expect(decoded == original)
        #expect(decoded.agentName == "claude-code")
    }

    @Test func fullSnapshotRoundtrip() throws {
        let paneID = UUID()
        let snapshot = OrchestrationSnapshot(
            panes: [
                PaneSnapshot(id: paneID, title: "claude", isCurrent: true),
                PaneSnapshot(id: UUID(), title: "opencode", agentStatus: .running)
            ],
            currentPaneID: paneID,
            pendingApprovals: [],
            worktrees: [WorktreeSnapshot(branch: "main", path: "/repo")],
            appVersion: "0.8.0",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(OrchestrationSnapshot.self, from: data)
        #expect(decoded.panes.count == 2)
        #expect(decoded.currentPaneID == paneID)
        #expect(decoded.appVersion == "0.8.0")
        #expect(decoded.worktrees.first?.branch == "main")
    }

    @Test func allAgentStatusesPreserved() throws {
        for status in AgentStatus.allCases {
            let pane = PaneSnapshot(
                id: UUID(), title: "test", agentStatus: status)
            let data = try encoder.encode(pane)
            let decoded = try decoder.decode(PaneSnapshot.self, from: data)
            #expect(decoded.agentStatus == status)
        }
    }
}

// MARK: - Equatable conformances for test comparison

extension OrchestrationSnapshot: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.panes == rhs.panes &&
        lhs.currentPaneID == rhs.currentPaneID &&
        lhs.pendingApprovals == rhs.pendingApprovals &&
        lhs.worktrees == rhs.worktrees &&
        lhs.appVersion == rhs.appVersion &&
        abs(lhs.capturedAt.timeIntervalSince(rhs.capturedAt)) < 1.0
    }
}
extension PaneSnapshot: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title &&
        lhs.workingDirectory == rhs.workingDirectory &&
        lhs.agentStatus == rhs.agentStatus &&
        lhs.agentStatusSource == rhs.agentStatusSource &&
        lhs.agentDetail == rhs.agentDetail &&
        lhs.isCurrent == rhs.isCurrent &&
        lhs.isZoomed == rhs.isZoomed &&
        lhs.worktreeBranch == rhs.worktreeBranch
    }
}
extension WorktreeSnapshot: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.branch == rhs.branch && lhs.path == rhs.path &&
        lhs.hasUncommittedChanges == rhs.hasUncommittedChanges &&
        lhs.linkedPaneID == rhs.linkedPaneID
    }
}
extension ApprovalSummary: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.paneID == rhs.paneID && lhs.agentName == rhs.agentName &&
        lhs.promptSummary == rhs.promptSummary &&
        abs(lhs.waitingSince.timeIntervalSince(rhs.waitingSince)) < 1.0
    }
}
