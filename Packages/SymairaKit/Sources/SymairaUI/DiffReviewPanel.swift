import SwiftUI
import WorktreeKit

public struct DiffReviewPanel: View {
    @ObservedObject var worktreeStore: WorktreeStore
    @State private var selectedWorktree: Worktree?
    @State private var diff: String = ""
    @State private var isLoading = false
    @State private var error: String?

    public init(worktreeStore: WorktreeStore) {
        self.worktreeStore = worktreeStore
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Review Panel")
                    .font(.headline)
                Spacer()
                if let worktree = selectedWorktree {
                    Text(worktree.taskID)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()

            Divider()

            if let error = error {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
            } else if isLoading {
                ProgressView("Loading diff...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if diff.isEmpty {
                Text("Select a worktree to review")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DiffView(diff: diff)
            }

            Divider()

            HStack {
                Picker("Worktree", selection: $selectedWorktree) {
                    Text("None").tag(nil as Worktree?)
                    ForEach(worktreeStore.worktrees, id: \.taskID) { worktree in
                        Text(worktree.taskID).tag(worktree as Worktree?)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 200)

                Spacer()

                Button("Copy Diff") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(diff, forType: .string)
                }
                .disabled(diff.isEmpty)

                Button("Refresh") {
                    loadDiff()
                }
                .disabled(selectedWorktree == nil)
            }
            .padding()
        }
        .frame(minWidth: 400, minHeight: 300)
        .onChange(of: selectedWorktree) {
            loadDiff()
        }
    }

    private func loadDiff() {
        guard let worktree = selectedWorktree else {
            diff = ""
            return
        }

        isLoading = true
        error = nil

        Task {
            do {
                let result = try worktreeStore.diff(worktree)
                await MainActor.run {
                    self.diff = result
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
}
