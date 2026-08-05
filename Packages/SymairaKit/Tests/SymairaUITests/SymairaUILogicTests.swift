import Foundation
import Testing
@testable import ProviderKit
@testable import SymairaUI

// MARK: - ProviderStore

@Suite(.serialized) @MainActor struct ProviderStoreTests {
    private func makeStore() throws -> (ProviderStore, URL) {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProviderStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let store = ProviderStore(
            keyStore: InMemoryKeyStore(),
            tokenStore: InMemoryTokenStore(),
            configManager: WorkspaceConfigManager(workspaceURL: workspace)
        )
        return (store, workspace)
    }

    @Test func setAndDeleteKey() throws {
        let (store, workspace) = try makeStore()
        defer { try? FileManager.default.removeItem(at: workspace) }

        #expect(!store.hasKey(for: .anthropic))
        try store.setKey("sk-ant-test-1", for: .anthropic)
        #expect(store.hasKey(for: .anthropic))
        #expect(store.key(for: .anthropic) == "sk-ant-test-1")

        store.deleteKey(for: .anthropic)
        #expect(!store.hasKey(for: .anthropic))
    }

    @Test func loadKeysFromStores() throws {
        let (store, workspace) = try makeStore()
        defer { try? FileManager.default.removeItem(at: workspace) }

        try store.setKey("sk-test-2", for: .openai)
        let reloaded = ProviderStore(
            keyStore: InMemoryKeyStore(),
            tokenStore: InMemoryTokenStore(),
            configManager: WorkspaceConfigManager(workspaceURL: workspace)
        )
        // The in-memory stores are per-instance, so a fresh store starts empty.
        #expect(!reloaded.hasKey(for: .openai))
    }

    @Test func oauthTokenLifecycle() throws {
        let (store, workspace) = try makeStore()
        defer { try? FileManager.default.removeItem(at: workspace) }

        #expect(!store.hasOAuthToken(for: .openai))
        try store.setOAuthToken(
            OAuthToken(accessToken: "at-1", refreshToken: "rt-1", expiresAt: Date().addingTimeInterval(3600)),
            for: .openai
        )
        #expect(store.hasOAuthToken(for: .openai))
        store.signOutOAuth(for: .openai)
        #expect(!store.hasOAuthToken(for: .openai))
    }

    @Test func switchProfileReloadsKeys() throws {
        let (store, workspace) = try makeStore()
        defer { try? FileManager.default.removeItem(at: workspace) }

        #expect(store.activeProfile == "default")
        try store.addProfile("business")
        #expect(store.profiles.contains("business"))

        try store.setKey("sk-default", for: .anthropic)
        try store.switchProfile(to: "business")
        #expect(store.activeProfile == "business")
        #expect(!store.hasKey(for: .anthropic))

        try store.switchProfile(to: "default")
        #expect(store.hasKey(for: .anthropic))
    }
}

// MARK: - FixErrorService

@Suite struct FixErrorServiceTests {
    @Test func prepareOutputRedactsSecrets() {
        let service = FixErrorService(keyStore: InMemoryKeyStore())
        let result = service.prepareOutput("curl failed with key sk-ant-api03-ABCDEFghijklmnop1234567890")
        #expect(!result.text.contains("sk-ant-api03"))
        #expect(result.text.contains("[REDACTED"))
    }

    @Test func prepareOutputKeepsPlainText() {
        let service = FixErrorService(keyStore: InMemoryKeyStore())
        let result = service.prepareOutput("error: file not found")
        #expect(result.text == "error: file not found")
        #expect(result.redactionCount == 0)
    }

    @Test func buildPromptThrowsWithoutKey() async {
        let service = FixErrorService(keyStore: InMemoryKeyStore())
        do {
            _ = try await service.buildPrompt(
                commandOutput: "some error output",
                provider: .anthropic,
                profile: "default"
            )
            Issue.record("Expected ProviderError.missingKey")
        } catch let error as ProviderError {
            if case .missingKey = error {
                // expected
            } else {
                Issue.record("Expected missingKey, got \(error)")
            }
        } catch {
            Issue.record("Expected ProviderError, got \(error)")
        }
    }
}

// MARK: - STTService

@Suite @MainActor struct STTServiceTests {
    @Test func startRecordingThrowsWhenRecognizerUnavailable() throws {
        // A locale the speech recognizer does not support yields a nil
        // recognizer, making the error path deterministic in headless CI.
        let service = STTService(locale: Locale(identifier: "zz-ZZ"))
        #expect(throws: STTError.self) {
            try service.startRecording()
        }
    }

    @Test func startsIdle() {
        let service = STTService(locale: Locale(identifier: "zz-ZZ"))
        #expect(!service.isRecording)
        #expect(service.recognizedText.isEmpty)
    }
}
