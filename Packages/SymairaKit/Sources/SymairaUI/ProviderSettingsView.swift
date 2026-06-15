import SwiftUI
import ProviderKit

public struct ProviderSettingsView: View {
    @ObservedObject var store: ProviderStore
    @State private var selectedProvider: ProviderID?
    @State private var isEditing = false

    public init(store: ProviderStore) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Providers")
                    .font(.headline)
                Spacer()
                Picker("Profile", selection: $store.activeProfile) {
                    ForEach(store.profiles, id: \.self) { profile in
                        Text(profile).tag(profile)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 150)
            }
            .padding()

            Divider()

            List {
                ForEach(ProviderID.allCases, id: \.self) { provider in
                    ProviderRow(
                        provider: provider,
                        store: store,
                        isSelected: selectedProvider == provider,
                        onSelect: { selectedProvider = provider }
                    )
                }
            }
            .listStyle(.sidebar)
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}

struct ProviderRow: View {
    let provider: ProviderID
    @ObservedObject var store: ProviderStore
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isEditing = false
    @State private var keyValue = ""
    @State private var isRevealed = false
    @State private var isSigningIn = false
    @State private var oauthError: String?

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: iconForProvider(provider))
                    .foregroundColor(.accentColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                        .font(.body)
                    if provider.supportsOAuth {
                        if store.hasOAuthToken(for: provider) {
                            Text("Signed in with OAuth")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Text("Not signed in")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        if let key = store.key(for: provider) {
                            Text(isRevealed ? key : maskedKey(key))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("No key set")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    if let defaultModel = ProviderChatClient.defaultModels[provider], !defaultModel.isEmpty {
                        Text("Default model: \(defaultModel)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if let error = oauthError {
                        Text(error)
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }

                Spacer()

                if provider.supportsOAuth {
                    if store.hasOAuthToken(for: provider) {
                        Button {
                            store.signOutOAuth(for: provider)
                        } label: {
                            Text("Sign Out")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            signInWithOAuth()
                        } label: {
                            if isSigningIn {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Sign In")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isSigningIn)
                    }
                } else if store.hasKey(for: provider) {
                    Button {
                        isRevealed.toggle()
                    } label: {
                        Image(systemName: isRevealed ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)

                    Button {
                        isEditing = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)

                    Button {
                        store.deleteKey(for: provider)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        isEditing = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isEditing) {
            APIKeyEditorSheet(
                provider: provider,
                store: store,
                isPresented: $isEditing
            )
        }
    }

    private func signInWithOAuth() {
        isSigningIn = true
        oauthError = nil
        Task {
            do {
                try await store.signInWithOAuth(for: provider)
            } catch {
                oauthError = error.localizedDescription
            }
            isSigningIn = false
        }
    }

    private func maskedKey(_ key: String) -> String {
        guard key.count > 8 else { return "••••••••" }
        let prefix = key.prefix(4)
        let suffix = key.suffix(4)
        return "\(prefix)••••••\(suffix)"
    }

    private func iconForProvider(_ provider: ProviderID) -> String {
        switch provider {
        case .anthropic: return "brain.head.profile"
        case .openai: return "sparkle"
        case .openrouter: return "arrow.triangle.branch"
        case .google: return "globe"
        case .ollama: return "desktopcomputer"
        case .openAICompatible: return "network"
        }
    }
}

struct APIKeyEditorSheet: View {
    let provider: ProviderID
    @ObservedObject var store: ProviderStore
    @Binding var isPresented: Bool

    @State private var keyValue = ""
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Add \(provider.displayName) API Key")
                .font(.headline)

            SecureField("API Key", text: $keyValue)
                .textFieldStyle(.roundedBorder)

            if let error = error {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                Spacer()
                Button("Save") {
                    save()
                }
                .disabled(keyValue.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            if let existing = store.key(for: provider) {
                keyValue = existing
            }
        }
    }

    private func save() {
        do {
            try store.setKey(keyValue, for: provider)
            isPresented = false
        } catch {
            self.error = error.localizedDescription
        }
    }
}
