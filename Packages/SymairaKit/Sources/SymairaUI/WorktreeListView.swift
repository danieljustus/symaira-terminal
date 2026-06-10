import SwiftUI
import WorktreeKit

public struct WorktreeListView: View {
    @ObservedObject var store: WorktreeStore
    let onSelect: (Worktree) -> Void
    let onCreate: () -> Void
    let onRemove: (Worktree) -> Void

    public init(
        store: WorktreeStore,
        onSelect: @escaping (Worktree) -> Void,
        onCreate: @escaping () -> Void,
        onRemove: @escaping (Worktree) -> Void
    ) {
        self.store = store
        self.onSelect = onSelect
        self.onCreate = onCreate
        self.onRemove = onRemove
    }

    public var body: some View {
        Section {
            if store.worktrees.isEmpty {
                Text("No active worktrees")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(store.worktrees, id: \.taskID) { worktree in
                    Button {
                        onSelect(worktree)
                    } label: {
                        WorktreeRow(worktree: worktree, store: store)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Open in Finder") {
                            NSWorkspace.shared.open(worktree.path)
                        }
                        Divider()
                        Button("Remove", role: .destructive) {
                            onRemove(worktree)
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text("Worktrees")
                Spacer()
                Button(action: onCreate) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct WorktreeRow: View {
    let worktree: Worktree
    @ObservedObject var store: WorktreeStore

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(store.isDirty(worktree) ? Color.orange : Color.green)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(worktree.taskID)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                Text(worktree.branch.replacingOccurrences(of: "refs/heads/", with: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(store.age(worktree))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
