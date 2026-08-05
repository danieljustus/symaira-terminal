import Testing
import Foundation
@testable import StackKit

@Suite(.serialized) @MainActor struct StackStoreTests {
    private func makeStore() -> StackStore {
        // Deterministic detector: an empty PATH finds nothing installed, so
        // scan() never depends on the runner's actual tool installation.
        StackStore(detector: StackDetector(pathEnvironment: "/nonexistent"))
    }

    @Test func initialCountsReflectRegistry() {
        let store = makeStore()
        #expect(store.totalCount == SymairaToolRegistry.all.count)
        #expect(store.installedCount == 0)
        #expect(store.detectedTools.isEmpty)
        #expect(!store.isScanning)
        #expect(store.lastScanDate == nil)
    }

    @Test func scanFlipsStateAndRecordsDate() async {
        let store = makeStore()
        await store.scan()
        #expect(!store.isScanning)
        #expect(store.lastScanDate != nil)
        #expect(store.error == nil)
        // Nothing on the injected empty PATH is installed.
        #expect(store.installedCount == 0)
    }

    @Test func exportPresetWritesValidJSONToURL() throws {
        let store = makeStore()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("preset-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try store.exportPreset(to: url)
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["mcpServers"] != nil)
        #expect(store.lastExportDate != nil)
        #expect(store.lastExportPath == url.path)
    }

    @Test func claudeCodeCommandsEmptyWithoutInstalledTools() {
        let store = makeStore()
        #expect(store.claudeCodeCommands.isEmpty)
    }

    @Test func presetWithNoInstalledToolsHasNoServers() {
        let store = makeStore()
        #expect(store.preset.mcpServers.isEmpty)
    }
}
