import SwiftUI
import ProviderKit

public struct OnboardingView: View {
    @ObservedObject var providerStore: ProviderStore
    @State private var currentStep = 0
    @State private var apiKey = ""
    @State private var selectedProvider: ProviderID = .anthropic
    @State private var isComplete = false
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
                .disabled(currentStep == 1 && apiKey.isEmpty)
            }
        }
        .padding(40)
        .frame(width: 500, height: 400)
    }

    private var stepOne: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Step 1: Add API Key")
                .font(.headline)

            Text("Bring your own API key. Keys stay in your macOS Keychain only.")
                .foregroundColor(.secondary)

            Picker("Provider", selection: $selectedProvider) {
                ForEach(ProviderID.allCases, id: \.self) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.menu)

            SecureField("API Key", text: $apiKey)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var stepTwo: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Step 2: Shell Integration")
                .font(.headline)

            Text("Enable OSC 133 shell integration for command blocks and prompt navigation.")
                .foregroundColor(.secondary)

            Text("Add to your shell rc file:")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("source /path/to/symaira-shell-integration.zsh")
                .font(.system(.caption, design: .monospaced))
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(4)
        }
    }

    private var stepThree: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Step 3: Ready to Go")
                .font(.headline)

            Text("You're all set! Start coding with AI agents in parallel.")
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                FeatureRow(icon: "brain.head.profile", text: "Agent status rings")
                FeatureRow(icon: "arrow.triangle.branch", text: "Git worktree isolation")
                FeatureRow(icon: "key.fill", text: "BYOK for all providers")
                FeatureRow(icon: "sparkle", text: "NL→Command generation")
            }
        }
    }

    private func complete() {
        if !apiKey.isEmpty {
            try? providerStore.setKey(apiKey, for: selectedProvider)
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
