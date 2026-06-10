import SwiftUI
import ContextBank

public struct ContextBankPanel: View {
    let repositoryURL: URL
    @State private var files: [ContextFile] = []
    @State private var selectedFile: ContextFile?
    @State private var isRefreshing = false

    private let locator = ContextFileLocator()

    public init(repositoryURL: URL) {
        self.repositoryURL = repositoryURL
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Context Bank")
                    .font(.headline)
                Spacer()
                Button {
                    refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(isRefreshing)
            }
            .padding()

            Divider()

            HSplitView {
                ContextFileListView(
                    files: files,
                    onSelect: { selectedFile = $0 },
                    onCreate: { createFile(kind: $0) }
                )
                .frame(minWidth: 180, idealWidth: 220)

                if let file = selectedFile {
                    ContextFileEditor(file: file)
                } else {
                    Text("Select a context file to edit")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            refresh()
        }
    }

    private func refresh() {
        isRefreshing = true
        files = locator.locate(in: repositoryURL)
        isRefreshing = false
    }

    private func createFile(kind: ContextFileKind) {
        let url = repositoryURL.appendingPathComponent(kind.rawValue)
        guard !FileManager.default.fileExists(atPath: url.path) else { return }

        let template = templateForKind(kind)
        do {
            try template.write(to: url, atomically: true, encoding: .utf8)
            refresh()
            selectedFile = ContextFile(kind: kind, url: url)
        } catch {
        }
    }

    private func templateForKind(_ kind: ContextFileKind) -> String {
        switch kind {
        case .claude:
            return """
            # CLAUDE.md

            ## Project Context
            <!-- Describe your project here -->

            ## Rules
            <!-- Add coding rules and conventions -->

            ## Examples
            <!-- Add examples of expected behavior -->
            """
        case .agents:
            return """
            # AGENTS.md

            ## Agent Instructions
            <!-- Instructions for AI agents working in this repo -->
            """
        case .gemini:
            return """
            # GEMINI.md

            ## Project Context
            <!-- Describe your project for Gemini -->
            """
        case .cursorRules:
            return """
            # Cursor Rules
            <!-- Rules for Cursor AI -->
            """
        }
    }
}
