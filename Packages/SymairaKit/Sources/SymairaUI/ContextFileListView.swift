import SwiftUI
import ContextBank

public struct ContextFileListView: View {
    let files: [ContextFile]
    let onSelect: (ContextFile) -> Void
    let onCreate: (ContextFileKind) -> Void

    public init(
        files: [ContextFile],
        onSelect: @escaping (ContextFile) -> Void,
        onCreate: @escaping (ContextFileKind) -> Void
    ) {
        self.files = files
        self.onSelect = onSelect
        self.onCreate = onCreate
    }

    public var body: some View {
        Section {
            if files.isEmpty {
                Text("No context files found")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(files, id: \.url) { file in
                    Button {
                        onSelect(file)
                    } label: {
                        HStack {
                            Image(systemName: iconForKind(file.kind))
                                .foregroundColor(.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.kind.rawValue)
                                    .font(.system(.body, design: .monospaced))
                                Text(file.url.deletingLastPathComponent().lastPathComponent)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            HStack {
                Text("Context Files")
                Spacer()
                Menu {
                    ForEach(ContextFileKind.allCases, id: \.self) { kind in
                        Button(kind.rawValue) {
                            onCreate(kind)
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
            }
        }
    }

    private func iconForKind(_ kind: ContextFileKind) -> String {
        switch kind {
        case .claude: return "brain.head.profile"
        case .agents: return "robot"
        case .gemini: return "sparkles"
        case .cursorRules: return "cursorarrow"
        }
    }
}
