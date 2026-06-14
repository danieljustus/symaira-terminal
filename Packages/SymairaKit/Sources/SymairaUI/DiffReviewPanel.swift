import AgentKit
import SwiftUI
import WorktreeKit

public struct DiffReviewPanel: View {
    @ObservedObject var worktreeStore: WorktreeStore
    @State private var selectedWorktree: Worktree?
    @State private var diff: String = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var selectedTab: ReviewTab = .diff
    @State private var transcripts: [TranscriptEntry] = []
    @State private var selectedTranscript: TranscriptEntry?

    public enum ReviewTab: String, CaseIterable {
        case diff = "Diff"
        case transcripts = "Transcripts"
    }

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

            Picker("Tab", selection: $selectedTab) {
                ForEach(ReviewTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            Divider()

            switch selectedTab {
            case .diff:
                diffContent
            case .transcripts:
                transcriptsContent
            }

            Divider()

            HStack {
                if selectedTab == .diff {
                    Picker("Worktree", selection: $selectedWorktree) {
                        Text("None").tag(nil as Worktree?)
                        ForEach(worktreeStore.worktrees, id: \.taskID) { worktree in
                            Text(worktree.taskID).tag(worktree as Worktree?)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200)
                }

                Spacer()

                if selectedTab == .diff {
                    Button("Copy Diff") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(diff, forType: .string)
                    }
                    .disabled(diff.isEmpty)

                    Button("Refresh") {
                        loadDiff()
                    }
                    .disabled(selectedWorktree == nil)
                } else {
                    Button("Refresh") {
                        loadTranscripts()
                    }
                }
            }
            .padding()
        }
        .frame(minWidth: 400, minHeight: 300)
        .onChange(of: selectedWorktree) {
            loadDiff()
        }
        .onAppear {
            loadTranscripts()
        }
    }

    private var diffContent: some View {
        Group {
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
        }
    }

    private var transcriptsContent: some View {
        Group {
            if transcripts.isEmpty {
                Text("No transcripts found")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(transcripts) { transcript in
                    Button {
                        selectedTranscript = transcript
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(transcript.id.uuidString.prefix(8) + "...")
                                .font(.system(.body, design: .monospaced))
                            Text(transcript.timestamp, style: .date)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(item: $selectedTranscript) { transcript in
            TranscriptDetailView(transcript: transcript)
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

    private func loadTranscripts() {
        transcripts = TranscriptStorage.shared.list()
    }
}

struct TranscriptDetailView: View {
    let transcript: TranscriptEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Transcript \(transcript.id.uuidString.prefix(8))...")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }
            .padding()

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(transcript.content.indices, id: \.self) { index in
                        let message = transcript.content[index]
                        VStack(alignment: .leading, spacing: 4) {
                            Text(message.role.rawValue.uppercased())
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(message.content)
                                .textSelection(.enabled)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

extension TranscriptEntry: Identifiable {}

