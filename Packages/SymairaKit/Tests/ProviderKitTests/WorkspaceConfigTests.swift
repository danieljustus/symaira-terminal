import Foundation
import Testing
@testable import ProviderKit

@Suite struct WorkspaceConfigTests {
    @Test func defaultConfigHasOneProfile() {
        let config = WorkspaceConfig()
        #expect(config.activeProfile == "default")
        #expect(config.profiles.count == 1)
        #expect(config.profiles.first?.name == "default")
    }

    @Test func profileLookup() {
        let config = WorkspaceConfig(profiles: [
            WorkspaceConfig.ProfileConfig(name: "default"),
            WorkspaceConfig.ProfileConfig(name: "work"),
        ])
        #expect(config.profile(named: "work")?.name == "work")
        #expect(config.profile(named: "missing") == nil)
    }

    @Test func profileConfigHasNoKeys() {
        let profile = WorkspaceConfig.ProfileConfig(name: "default")
        let encoded = try! JSONEncoder().encode(profile)
        let json = String(data: encoded, encoding: .utf8)!
        #expect(!json.contains("providerKeys"))
    }
}

@Suite struct WorkspaceConfigManagerTests {
    @Test func saveAndLoadRoundtrip() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let manager = WorkspaceConfigManager(workspaceURL: tmp)

        try manager.addProfile("work")
        try manager.switchProfile(to: "work")

        let loaded = WorkspaceConfigManager(workspaceURL: tmp)
        #expect(loaded.config.activeProfile == "work")
        #expect(loaded.config.profiles.count == 2)

        try? FileManager.default.removeItem(at: tmp)
    }

    @Test func migrationStripsProviderKeys() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let configDir = tmp.appendingPathComponent(".symaira")
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        let legacyJSON: [String: Any] = [
            "activeProfile": "default",
            "profiles": [
                ["name": "default", "providerKeys": ["anthropic": "sk-ant-secret", "openai": "sk-openai-secret"]],
                ["name": "work", "providerKeys": ["google": "goog-key"]],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: legacyJSON)
        try data.write(to: configDir.appendingPathComponent("config.json"))

        let manager = WorkspaceConfigManager(workspaceURL: tmp)
        #expect(manager.config.activeProfile == "default")
        #expect(manager.config.profiles.count == 2)
        // Keys must not survive migration
        let saved = try JSONEncoder().encode(manager.config)
        let savedJSON = String(data: saved, encoding: .utf8)!
        #expect(!savedJSON.contains("sk-ant-secret"))
        #expect(!savedJSON.contains("sk-openai-secret"))
        #expect(!savedJSON.contains("goog-key"))
        #expect(!savedJSON.contains("providerKeys"))

        try? FileManager.default.removeItem(at: tmp)
    }

    @Test func saveNeverWritesKeys() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let manager = WorkspaceConfigManager(workspaceURL: tmp)
        try manager.save()

        let configFile = tmp.appendingPathComponent(".symaira/config.json")
        let data = try Data(contentsOf: configFile)
        let json = String(data: data, encoding: .utf8)!
        #expect(!json.contains("providerKeys"))

        try? FileManager.default.removeItem(at: tmp)
    }
}

@Suite struct AgentProfileTests {
    @Test func defaultConfigHasOneAgentProfile() {
        let config = WorkspaceConfig()
        #expect(config.activeAgentProfile == "default")
        #expect(config.agentProfiles.count == 1)
        #expect(config.agentProfiles.first?.name == "default")
        #expect(config.agentProfiles.first?.mode == "strategic")
    }

    @Test func agentProfileLookup() {
        let config = WorkspaceConfig(agentProfiles: [
            WorkspaceConfig.AgentProfileConfig(name: "default"),
            WorkspaceConfig.AgentProfileConfig(name: "production", mode: "yolo"),
        ])
        #expect(config.agentProfile(named: "production")?.mode == "yolo")
        #expect(config.agentProfile(named: "missing") == nil)
    }

    @Test func agentProfilePersistence() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let manager = WorkspaceConfigManager(workspaceURL: tmp)

        let profile = WorkspaceConfig.AgentProfileConfig(
            name: "strict",
            mode: "strategic",
            rules: ["Use pnpm", "Run tests before pushing"]
        )
        try manager.addAgentProfile(profile)
        try manager.switchAgentProfile(to: "strict")

        let loaded = WorkspaceConfigManager(workspaceURL: tmp)
        #expect(loaded.config.activeAgentProfile == "strict")
        #expect(loaded.config.agentProfiles.count == 2)
        #expect(loaded.config.agentProfile(named: "strict")?.rules.count == 2)

        try? FileManager.default.removeItem(at: tmp)
    }

    @Test func agentProfileUpdate() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let manager = WorkspaceConfigManager(workspaceURL: tmp)

        var profile = WorkspaceConfig.AgentProfileConfig(name: "dev")
        try manager.addAgentProfile(profile)

        profile.mode = "yolo"
        profile.rules = ["No rules"]
        try manager.updateAgentProfile(profile)

        let loaded = WorkspaceConfigManager(workspaceURL: tmp)
        #expect(loaded.config.agentProfile(named: "dev")?.mode == "yolo")
        #expect(loaded.config.agentProfile(named: "dev")?.rules == ["No rules"])

        try? FileManager.default.removeItem(at: tmp)
    }

    @Test func agentProfileRemove() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let manager = WorkspaceConfigManager(workspaceURL: tmp)

        let profile = WorkspaceConfig.AgentProfileConfig(name: "temp")
        try manager.addAgentProfile(profile)
        try manager.removeAgentProfile("temp")

        #expect(manager.config.agentProfiles.count == 1)
        #expect(manager.config.agentProfile(named: "temp") == nil)

        try? FileManager.default.removeItem(at: tmp)
    }

    @Test func cannotRemoveDefaultAgentProfile() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let manager = WorkspaceConfigManager(workspaceURL: tmp)

        try manager.removeAgentProfile("default")
        #expect(manager.config.agentProfiles.count == 1)

        try? FileManager.default.removeItem(at: tmp)
    }
}
