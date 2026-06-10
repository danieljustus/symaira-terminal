import SwiftUI
import AgentKit

public struct FixErrorButton: View {
    let exitCode: Int32
    let commandOutput: String
    let onFix: (String) -> Void

    @State private var isHovering = false

    public init(exitCode: Int32, commandOutput: String, onFix: @escaping (String) -> Void) {
        self.exitCode = exitCode
        self.commandOutput = commandOutput
        self.onFix = onFix
    }

    public var body: some View {
        Button {
            onFix(commandOutput)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "wrench.fill")
                    .font(.caption)
                Text("Fix Error")
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.2))
            .foregroundColor(.orange)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .help("Send error to AI for fix suggestion")
    }
}

public struct FixErrorOverlay: View {
    let error: FixError
    let onDismiss: () -> Void
    let onApply: (String) -> Void

    public init(error: FixError, onDismiss: @escaping () -> Void, onApply: @escaping (String) -> Void) {
        self.error = error
        self.onDismiss = onDismiss
        self.onApply = onApply
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Error Detected")
                    .font(.headline)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text("Exit code: \(error.exitCode)")
                .font(.caption)
                .foregroundColor(.secondary)

            if !error.commandOutput.isEmpty {
                ScrollView {
                    Text(error.commandOutput)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(10)
                }
                .frame(maxHeight: 150)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(4)
            }

            HStack {
                Spacer()
                Button("Fix with AI") {
                    onApply(error.commandOutput)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .shadow(radius: 4)
    }
}

public struct FixError: Identifiable {
    public let id = UUID()
    public let exitCode: Int32
    public let commandOutput: String
    public let timestamp: Date

    public init(exitCode: Int32, commandOutput: String) {
        self.exitCode = exitCode
        self.commandOutput = commandOutput
        self.timestamp = Date()
    }
}
