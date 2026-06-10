import SwiftUI
import AgentKit
import SymairaUI
import WorktreeKit

struct PaneListItem: Identifiable {
    let id: UUID
    let title: String
    let status: AgentStatus
    let isActive: Bool
}

struct GitInfo: Equatable {
    let branch: String
    let isDirty: Bool
}

struct ChangedFile: Identifiable {
    let id = UUID()
    let path: String
    let status: FileChangeStatus
}

enum FileChangeStatus: String {
    case added = "A"
    case modified = "M"
    case deleted = "D"
    case renamed = "R"
    case untracked = "?"
}

struct ListeningPort: Identifiable {
    let id = UUID()
    let port: UInt16
    let process: String
    let protocol_: String
}

struct WorkspaceSidebar: View {
    let paneItems: [PaneListItem]
    let gitInfo: GitInfo?
    let changedFiles: [ChangedFile]
    let listeningPorts: [ListeningPort]
    let onSelectPane: (UUID) -> Void
    let onOpenPort: (UInt16) -> Void

    @ObservedObject var worktreeStore: WorktreeStore
    let onSelectWorktree: (Worktree) -> Void
    let onCreateWorktree: () -> Void
    let onRemoveWorktree: (Worktree) -> Void

    var body: some View {
        List {
            if let git = gitInfo {
                Section {
                    HStack {
                        Image(systemName: "arrow.triangle.branch")
                        Text(git.branch)
                            .font(.system(.body, design: .monospaced))
                        if git.isDirty {
                            Text("●")
                                .foregroundColor(.orange)
                                .font(.caption)
                        }
                    }
                } header: {
                    Text("Git")
                }
            }

            if !changedFiles.isEmpty {
                Section {
                    ForEach(changedFiles.prefix(10)) { file in
                        HStack(spacing: 6) {
                            Text(file.status.rawValue)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 12)
                            Text((file.path as NSString).lastPathComponent)
                                .lineLimit(1)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                        }
                    }
                    if changedFiles.count > 10 {
                        Text("+\(changedFiles.count - 10) more")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Changed Files (\(changedFiles.count))")
                }
            }

            WorktreeListView(
                store: worktreeStore,
                onSelect: onSelectWorktree,
                onCreate: onCreateWorktree,
                onRemove: onRemoveWorktree
            )

            if !listeningPorts.isEmpty {
                Section {
                    ForEach(listeningPorts) { port in
                        Button {
                            onOpenPort(port.port)
                        } label: {
                            HStack {
                                Text("\(port.port)")
                                    .font(.system(.body, design: .monospaced))
                                Text(port.process)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(port.protocol_)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Listening Ports")
                }
            }

            Section {
                ForEach(paneItems) { item in
                    Button {
                        onSelectPane(item.id)
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(StatusRingStyle.color(for: item.status))
                                .frame(width: 8, height: 8)
                            Text(item.title)
                                .lineLimit(1)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            if item.isActive {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.accentColor)
                                    .font(.caption)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Panes")
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180, idealWidth: 220)
    }
}
