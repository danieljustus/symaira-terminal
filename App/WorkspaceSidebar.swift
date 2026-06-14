import SwiftUI
import AgentKit
import SymairaUI
import WorktreeKit

public struct PaneStatusInfo: Identifiable, Equatable {
    public let id: UUID
    public let index: Int
    public let title: String
    public let status: AgentStatus
    public let isActive: Bool
    public let cwd: URL?
    public let gitBranch: String?
    public let gitIsDirty: Bool
    public let gitAhead: Int
    public let gitBehind: Int
    public let prNumber: Int?
    public let prTitle: String?
    public let prStatus: String?
    public let listeningPorts: [UInt16]
    
    public init(
        id: UUID,
        index: Int,
        title: String,
        status: AgentStatus,
        isActive: Bool,
        cwd: URL?,
        gitBranch: String?,
        gitIsDirty: Bool,
        gitAhead: Int,
        gitBehind: Int,
        prNumber: Int?,
        prTitle: String?,
        prStatus: String?,
        listeningPorts: [UInt16]
    ) {
        self.id = id
        self.index = index
        self.title = title
        self.status = status
        self.isActive = isActive
        self.cwd = cwd
        self.gitBranch = gitBranch
        self.gitIsDirty = gitIsDirty
        self.gitAhead = gitAhead
        self.gitBehind = gitBehind
        self.prNumber = prNumber
        self.prTitle = prTitle
        self.prStatus = prStatus
        self.listeningPorts = listeningPorts
    }
}

@MainActor
public final class SidebarViewModel: ObservableObject {
    @Published public var paneItems: [PaneStatusInfo] = []
    @Published public var worktreeStore: WorktreeStore
    
    public init(worktreeStore: WorktreeStore) {
        self.worktreeStore = worktreeStore
    }
}

public struct WorkspaceSidebar: View {
    @ObservedObject public var viewModel: SidebarViewModel
    public let onSelectPane: (UUID) -> Void
    public let onOpenPort: (UInt16) -> Void
    
    // Worktree callbacks
    public let onSelectWorktree: (Worktree) -> Void
    public let onCreateWorktree: () -> Void
    public let onRemoveWorktree: (Worktree) -> Void
    
    @State private var hoveredPaneID: UUID? = nil

    public init(
        viewModel: SidebarViewModel,
        onSelectPane: @escaping (UUID) -> Void,
        onOpenPort: @escaping (UInt16) -> Void,
        onSelectWorktree: @escaping (Worktree) -> Void,
        onCreateWorktree: @escaping () -> Void,
        onRemoveWorktree: @escaping (Worktree) -> Void
    ) {
        self.viewModel = viewModel
        self.onSelectPane = onSelectPane
        self.onOpenPort = onOpenPort
        self.onSelectWorktree = onSelectWorktree
        self.onCreateWorktree = onCreateWorktree
        self.onRemoveWorktree = onRemoveWorktree
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("SYMAIRA DEV")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .tracking(1.5)
                Spacer()
                
                // Active agent indicators summary
                let activeCount = viewModel.paneItems.filter { $0.status == .running || $0.status == .awaitingApproval }.count
                if activeCount > 0 {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("\(activeCount) active")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            // Main list split into tabs and worktrees
            List {
                Section {
                    if viewModel.paneItems.isEmpty {
                        Text("No active tabs")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(viewModel.paneItems) { pane in
                            Button {
                                onSelectPane(pane.id)
                            } label: {
                                PaneTabCard(
                                    pane: pane,
                                    isHovered: hoveredPaneID == pane.id,
                                    onOpenPort: onOpenPort
                                )
                            }
                            .buttonStyle(.plain)
                            .onHover { isHovered in
                                hoveredPaneID = isHovered ? pane.id : nil
                            }
                        }
                    }
                } header: {
                    Text("Smart Tabs")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                
                WorktreeListView(
                    store: viewModel.worktreeStore,
                    onSelect: onSelectWorktree,
                    onCreate: onCreateWorktree,
                    onRemove: onRemoveWorktree
                )
            }
            .listStyle(.sidebar)
        }
        .frame(minWidth: 240, idealWidth: 260)
    }
}

struct PaneTabCard: View {
    let pane: PaneStatusInfo
    let isHovered: Bool
    let onOpenPort: (UInt16) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top Row: Title, Status Indicator, Active Checkmark
            HStack(alignment: .center, spacing: 6) {
                // Agent status dot
                Circle()
                    .fill(StatusRingStyle.color(for: pane.status))
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(StatusRingStyle.color(for: pane.status), lineWidth: 1)
                            .scaleEffect(pane.status == .awaitingApproval || pane.status == .error ? 1.8 : 1.0)
                            .opacity(pane.status == .awaitingApproval || pane.status == .error ? 0.3 : 0.0)
                    )
                
                // Tab label & directory/title
                Text("\(pane.index + 1)")
                    .font(.system(.subheadline, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(pane.isActive ? .primary : .secondary)
                
                let folderName = pane.cwd?.lastPathComponent ?? "Terminal"
                Text(pane.title == "Terminal" ? folderName : pane.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(pane.isActive ? .primary : .primary.opacity(0.8))
                    .lineLimit(1)
                
                Spacer()
                
                if pane.isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.accentColor)
                }
            }
            
            // CWD Subtitle
            if let cwd = pane.cwd {
                let displayPath = cwd.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
                Text(displayPath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(pane.isActive ? .primary.opacity(0.7) : .secondary)
                    .lineLimit(1)
            }
            
            // Git row
            if let branch = pane.gitBranch {
                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 10))
                        Text(branch)
                            .font(.system(size: 11, design: .monospaced))
                        if pane.gitIsDirty {
                            Text("●")
                                .foregroundColor(.orange)
                                .font(.system(size: 8))
                        }
                    }
                    .foregroundColor(pane.isActive ? .primary.opacity(0.8) : .secondary)
                    
                    // Ahead / Behind indicators
                    if pane.gitAhead > 0 || pane.gitBehind > 0 {
                        HStack(spacing: 3) {
                            if pane.gitAhead > 0 {
                                Text("↑\(pane.gitAhead)")
                                    .foregroundColor(.green)
                            }
                            if pane.gitBehind > 0 {
                                Text("↓\(pane.gitBehind)")
                                    .foregroundColor(.red)
                            }
                        }
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                    }
                }
            }
            
            // Pull Request Progress badge
            if let prNum = pane.prNumber, let prTitle = pane.prTitle, let prState = pane.prStatus {
                HStack(spacing: 4) {
                    Image(systemName: "checklist")
                        .font(.system(size: 9))
                    Text("PR #\(prNum)")
                        .fontWeight(.bold)
                    Text(prState.capitalized)
                        .font(.system(size: 9, weight: .semibold))
                }
                .font(.system(size: 9))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(prBadgeColor(for: prState).opacity(0.15))
                .foregroundColor(prBadgeColor(for: prState))
                .cornerRadius(4)
                .help(prTitle)
            }
            
            // Ports Row
            if !pane.listeningPorts.isEmpty {
                HStack(spacing: 4) {
                    ForEach(pane.listeningPorts, id: \.self) { port in
                        Button {
                            onOpenPort(port)
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "network")
                                    .font(.system(size: 8))
                                Text("\(port)")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(pane.isActive ? Color.white.opacity(0.2) : Color.secondary.opacity(0.15))
                            .foregroundColor(pane.isActive ? .primary : .accentColor)
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    pane.isActive
                        ? AnyShapeStyle(LinearGradient(
                            colors: [Color.accentColor.opacity(0.2), Color.accentColor.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                          ))
                        : AnyShapeStyle(Color.secondary.opacity(isHovered ? 0.08 : 0.03))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    pane.isActive ? Color.accentColor.opacity(0.4) : Color.clear,
                    lineWidth: 1
                )
        )
        .padding(.vertical, 2)
    }
    
    private func prBadgeColor(for state: String) -> Color {
        switch state.lowercased() {
        case "approved": return .green
        case "changes_requested": return .red
        case "open": return .blue
        case "draft": return .secondary
        case "merged": return .purple
        default: return .secondary
        }
    }
}
