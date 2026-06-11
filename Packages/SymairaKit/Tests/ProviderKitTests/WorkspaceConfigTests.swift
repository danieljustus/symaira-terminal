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
