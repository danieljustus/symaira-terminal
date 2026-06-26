import SwiftUI
import AgentKit
import ProviderKit
import TerminalCore

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
    let provider: ProviderID
    let providerBaseURL: String?
    let onDismiss: () -> Void
    let onApply: (String) -> Void

    @State private var redactedResult: RedactionResult?
    @State private var showConfirmation = false

    private var isLocalProvider: Bool {
        provider == .ollama
    }

    public init(
        error: FixError,
        provider: ProviderID = .ollama,
        providerBaseURL: String? = nil,
        onDismiss: @escaping () -> Void,
        onApply: @escaping (String) -> Void
    ) {
        self.error = error
        self.provider = provider
        self.providerBaseURL = providerBaseURL
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

            HStack(spacing: 4) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Sending to: \(providerDisplayName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let baseURL = providerBaseURL {
                    Text("(\(baseURL))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if let result = redactedResult {
                if result.redactionCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "shield.checkered")
                            .font(.caption)
                            .foregroundColor(.green)
                        Text("\(result.redactionCount) secret(s) redacted")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }

                ScrollView {
                    Text(result.displayText)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(10)
                }
                .frame(maxHeight: 150)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(4)
            } else {
                ProgressView()
                    .controlSize(.small)
            }

            HStack {
                Spacer()
                if !isLocalProvider && !showConfirmation {
                    Button("Review before sending") {
                        showConfirmation = true
                    }
                    .buttonStyle(.bordered)
                }
                Button("Fix with AI") {
                    if let result = redactedResult {
                        onApply(result.text)
                    } else {
                        onApply(error.commandOutput)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(redactedResult == nil)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .shadow(radius: 4)
        .onAppear {
            let redactor = SecretRedactor()
            redactedResult = redactor.redact(error.commandOutput)
        }
    }

    private var providerDisplayName: String {
        switch provider {
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        case .openrouter: return "OpenRouter"
        case .google: return "Google"
        case .ollama: return "Ollama (local)"
        case .openAICompatible: return "Custom Provider"
        }
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
