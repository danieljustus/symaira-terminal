import AppKit
import SwiftUI
import ProviderKit

public struct OnboardingView: View {
    @ObservedObject var providerStore: ProviderStore
    @State private var currentStep = 0
    @State private var apiKey = ""
    @State private var selectedProvider: ProviderID = .anthropic
    @State private var keySaved = false
    @State private var keyError: String?
    @Binding var isPresented: Bool

    public init(providerStore: ProviderStore, isPresented: Binding<Bool>) {
        self.providerStore = providerStore
        self._isPresented = isPresented
    }

    public var body: some View {
        VStack(spacing: 24) {
            HStack {
                Spacer()
                Button("Skip") {
                    complete()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "terminal.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("Welcome to Symaira Terminal")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("A native macOS terminal built for the Human-AI era.")
                .font(.title3)
                .foregroundColor(.secondary)

            Spacer()

            if currentStep == 0 {
                stepOne
            } else if currentStep == 1 {
                stepTwo
            } else {
                stepThree
            }

            Spacer()

            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        currentStep -= 1
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button(currentStep < 2 ? "Next" : "Get Started") {
                    if currentStep < 2 {
                        currentStep += 1
                    } else {
                        complete()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(40)
        .frame(width: 500, height: 400)
    }

    private var stepOne: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Step 1: Add an API key (optional)")
                .font(.headline)

            Text("Bring your own key for AI features. Keys stay in your macOS Keychain only — you can also add one later in Settings.")
                .foregroundColor(.secondary)

            Picker("Provider", selection: $selectedProvider) {
                ForEach(ProviderID.allCases, id: \.self) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedProvider) { _, _ in
                keySaved = false
                keyError = nil
            }

            HStack {
                SecureField("API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: apiKey) { _, _ in
                        keySaved = false
                        keyError = nil
                    }

                Button("Save") {
                    saveKey()
                }
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if keySaved {
                Label("Saved to Keychain", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            } else if let keyError {
                Label(keyError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    private var stepTwo: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Step 2: Shell integration (optional)")
                .font(.headline)

            Text(
                "Enable OSC 133 shell integration for command blocks, prompt navigation, "
                + "and agent status. Add this line to your shell config, then restart your shell."
            )
                .foregroundColor(.secondary)

            if let path = shellIntegrationPath {
                let line = "source \"\(path)\""
                HStack(alignment: .top) {
                    Text(line)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(4)

                    Button {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(line, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .help("Copy to clipboard")
                }
            } else {
                Text("Shell integration script not found in the app bundle. You can skip this step and enable it later from Settings.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var stepThree: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Step 3: You're ready")
                .font(.headline)

            Text("Your terminal is ready to use. Press ⌘T to open a new tab, or ⌘D to split the current pane.")
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                FeatureRow(icon: "brain.head.profile", text: "Agent status rings")
                FeatureRow(icon: "arrow.triangle.branch", text: "Git worktree isolation")
                FeatureRow(icon: "key.fill", text: "BYOK for all providers")
                FeatureRow(icon: "sparkle", text: "NL→Command generation")
            }
        }
    }

    /// Resolved, real path to the bundled shell-integration script for the
    /// user's current shell. Nil when running outside the app bundle (previews,
    /// tests) or if the resource is missing.
    private var shellIntegrationPath: String? {
        let shell = (ProcessInfo.processInfo.environment["SHELL"] as NSString?)?.lastPathComponent ?? "zsh"
        let resource: (name: String, ext: String)
        switch shell {
        case "bash": resource = ("symaira-bash-integration", "bash")
        case "fish": resource = ("symaira-fish-integration", "fish")
        default: resource = ("symaira-zsh-integration", "zsh")
        }
        return Bundle.main.url(forResource: resource.name, withExtension: resource.ext)?.path
    }

    private func saveKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try providerStore.setKey(trimmed, for: selectedProvider)
            keySaved = true
            keyError = nil
        } catch {
            keySaved = false
            keyError = "Could not save key to Keychain."
        }
    }

    private func complete() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keySaved && !trimmed.isEmpty {
            try? providerStore.setKey(trimmed, for: selectedProvider)
        }
        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
        isPresented = false
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 20)
            Text(text)
        }
    }
}
