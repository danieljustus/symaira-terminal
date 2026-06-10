import Foundation
import AgentKit
import ProviderKit

public struct GeminiACPAdapter {
    private let client: ACPClient
    private let keyStore: KeyStore

    public init(client: ACPClient, keyStore: KeyStore = KeychainKeyStore()) {
        self.client = client
        self.keyStore = keyStore
    }

    public func start(profile: String) throws {
        guard let apiKey = try keyStore.key(provider: .google, profile: profile) else {
            throw GeminiError.missingAPIKey
        }

        var env = ProcessInfo.processInfo.environment
        env["GOOGLE_API_KEY"] = apiKey

        try client.start()
    }

    public func handleEvent(_ event: ACPEvent, completion: @escaping (ACPEvent) -> Void) {
        switch event {
        case .permissionRequest(let id, let toolName, let description):
            let normalizedTool = normalizeToolName(toolName)
            completion(.permissionRequest(id: id, toolName: normalizedTool, description: description))
        default:
            completion(event)
        }
    }

    private func normalizeToolName(_ name: String) -> String {
        switch name {
        case "write_file", "create_file": return "file-write"
        case "edit_file": return "file-edit"
        case "read_file": return "file-read"
        case "run_command", "execute_command": return "shell"
        case "search_files": return "search"
        default: return name
        }
    }
}

public enum GeminiError: Error, LocalizedError {
    case missingAPIKey

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Google API key not found in Keychain. Add it in Settings > Providers."
        }
    }
}
