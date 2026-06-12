import SwiftUI
import ProviderKit
import StackKit

public struct SettingsView: View {
    @ObservedObject var providerStore: ProviderStore
    @ObservedObject var workspaceConfigManager: WorkspaceConfigManager
    @ObservedObject var stackStore: StackStore
    @Binding var isPresented: Bool

    @AppStorage("defaultShell") private var defaultShell = "/bin/zsh"
    @AppStorage("scrollbackLines") private var scrollbackLines = 10000

    public init(
        providerStore: ProviderStore,
        workspaceConfigManager: WorkspaceConfigManager,
        stackStore: StackStore,
        isPresented: Binding<Bool>
    ) {
        self.providerStore = providerStore
        self.workspaceConfigManager = workspaceConfigManager
        self.stackStore = stackStore
        self._isPresented = isPresented
    }

    public var body: some View {
        TabView {
            GeneralSettingsView(
                defaultShell: $defaultShell,
                scrollbackLines: $scrollbackLines
            )
            .tabItem {
                Label("General", systemImage: "gear")
            }

            ProviderSettingsView(store: providerStore)
                .tabItem {
                    Label("Providers", systemImage: "key.fill")
                }

            StackSettingsView(store: stackStore)
                .tabItem {
                    Label("MCP Stack", systemImage: "server.rack")
                }

            WorkspaceSettingsView(workspaceConfigManager: workspaceConfigManager)
                .tabItem {
                    Label("Workspace", systemImage: "folder")
                }

            AdvancedSettingsView()
                .tabItem {
                    Label("Advanced", systemImage: "slider.horizontal.3")
                }
        }
        .frame(width: 500, height: 400)
        .padding()
    }
}

struct GeneralSettingsView: View {
    @Binding var defaultShell: String
    @Binding var scrollbackLines: Int

    var body: some View {
        Form {
            Section("Shell") {
                Picker("Default Shell", selection: $defaultShell) {
                    Text("/bin/zsh").tag("/bin/zsh")
                    Text("/bin/bash").tag("/bin/bash")
                    Text("/usr/local/bin/fish").tag("/usr/local/bin/fish")
                }
                .pickerStyle(.menu)
            }

            Section("Terminal") {
                HStack {
                    Text("Scrollback Lines")
                    Spacer()
                    TextField("", value: $scrollbackLines, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct WorkspaceSettingsView: View {
    @ObservedObject var workspaceConfigManager: WorkspaceConfigManager

    var body: some View {
        Form {
            Section("Profile") {
                Picker("Active Profile", selection: $workspaceConfigManager.config.activeProfile) {
                    ForEach(workspaceConfigManager.config.profiles, id: \.name) { profile in
                        Text(profile.name).tag(profile.name)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: workspaceConfigManager.config.activeProfile) {
                    try? workspaceConfigManager.save()
                }

                HStack {
                    Button("Add Profile") {
                        let name = "Profile \(workspaceConfigManager.config.profiles.count + 1)"
                        try? workspaceConfigManager.addProfile(name)
                    }
                    Button("Remove Profile", role: .destructive) {
                        try? workspaceConfigManager.removeProfile(workspaceConfigManager.config.activeProfile)
                    }
                    .disabled(workspaceConfigManager.config.activeProfile == "default")
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct AdvancedSettingsView: View {
    @AppStorage("debugLogging") private var debugLogging = false

    var body: some View {
        Form {
            Section("Debug") {
                Toggle("Enable debug logging", isOn: $debugLogging)
            }

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Build")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
