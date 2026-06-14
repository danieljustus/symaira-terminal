import SwiftUI
import AgentKit
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

            AgentProfileSettingsView(workspaceConfigManager: workspaceConfigManager)
                .tabItem {
                    Label("Agent Profiles", systemImage: "person.badge.gearshape")
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

    @AppStorage("keepAwakeAlways") private var keepAwakeAlways = false
    @AppStorage("keepAwakeWhileAgentRunning") private var keepAwakeWhileAgentRunning = true

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

            Section("Sleep Prevention") {
                Toggle("Keep Mac Awake Always", isOn: $keepAwakeAlways)
                Toggle("Keep Mac Awake While Agent is Running", isOn: $keepAwakeWhileAgentRunning)
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

struct AgentProfileSettingsView: View {
    @ObservedObject var workspaceConfigManager: WorkspaceConfigManager
    @State private var newProfileName = ""
    @State private var newRule = ""
    @State private var editingProfile: WorkspaceConfig.AgentProfileConfig?

    var body: some View {
        Form {
            Section("Active Agent Profile") {
                Picker("Profile", selection: $workspaceConfigManager.config.activeAgentProfile) {
                    ForEach(workspaceConfigManager.config.agentProfiles) { profile in
                        Text(profile.name).tag(profile.name)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: workspaceConfigManager.config.activeAgentProfile) {
                    try? workspaceConfigManager.save()
                }
            }

            Section("Profiles") {
                ForEach(workspaceConfigManager.config.agentProfiles) { profile in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(profile.name)
                                .font(.headline)
                            Text(profile.mode.capitalized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Edit") {
                            editingProfile = profile
                        }
                        Button("Delete", role: .destructive) {
                            try? workspaceConfigManager.removeAgentProfile(profile.name)
                        }
                        .disabled(profile.name == "default")
                    }
                }

                HStack {
                    TextField("New profile name", text: $newProfileName)
                    Button("Add") {
                        guard !newProfileName.isEmpty else { return }
                        let profile = WorkspaceConfig.AgentProfileConfig(name: newProfileName)
                        try? workspaceConfigManager.addAgentProfile(profile)
                        newProfileName = ""
                    }
                    .disabled(newProfileName.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editingProfile) { profile in
            AgentProfileEditSheet(
                profile: profile,
                workspaceConfigManager: workspaceConfigManager
            )
        }
    }
}

struct AgentProfileEditSheet: View {
    let profile: WorkspaceConfig.AgentProfileConfig
    @ObservedObject var workspaceConfigManager: WorkspaceConfigManager
    @Environment(\.dismiss) private var dismiss

    @State private var mode: String
    @State private var rules: [String]
    @State private var newRule = ""

    init(profile: WorkspaceConfig.AgentProfileConfig, workspaceConfigManager: WorkspaceConfigManager) {
        self.profile = profile
        self.workspaceConfigManager = workspaceConfigManager
        self._mode = State(initialValue: profile.mode)
        self._rules = State(initialValue: profile.rules)
    }

    var body: some View {
        Form {
            Section("Mode") {
                Picker("Operating Mode", selection: $mode) {
                    Text("Strategic").tag("strategic")
                    Text("YOLO").tag("yolo")
                }
                .pickerStyle(.segmented)

                Text(modeDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Rules") {
                ForEach(rules.indices, id: \.self) { index in
                    HStack {
                        Text(rules[index])
                        Spacer()
                        Button {
                            rules.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundColor(.red)
                        }
                    }
                }

                HStack {
                    TextField("Add rule...", text: $newRule)
                    Button {
                        guard !newRule.isEmpty else { return }
                        rules.append(newRule)
                        newRule = ""
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .disabled(newRule.isEmpty)
                }

                Menu("Suggested Rules") {
                    ForEach(AgentProfile.suggestedRules, id: \.self) { rule in
                        Button(rule) {
                            if !rules.contains(rule) {
                                rules.append(rule)
                            }
                        }
                    }
                }
            }

            Section {
                Button("Save") {
                    var updated = profile
                    updated.mode = mode
                    updated.rules = rules
                    try? workspaceConfigManager.updateAgentProfile(updated)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 500)
        .padding()
    }

    private var modeDescription: String {
        mode == "strategic"
            ? "Agent asks before running commands. Safe for production and critical code."
            : "Agent has full autonomy. Reports only when all tests pass."
    }
}
