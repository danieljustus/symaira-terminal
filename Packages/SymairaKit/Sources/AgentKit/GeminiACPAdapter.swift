import Foundation
import TerminalCore
import ProviderKit

public struct GeminiACPAdapter {
    private let configuration: ACPConfiguration
    private let client: ACPClient

    public init(
        executable: URL,
        arguments: [String] = [],
        apiKey: String,
        workingDirectory: URL? = nil
    ) {
        let config = ACPConfiguration.withProviderKey(
            executable: executable,
            arguments: arguments,
            keyName: "GOOGLE_API_KEY",
            keyValue: apiKey,
            workingDirectory: workingDirectory
        )
        self.configuration = config
        self.client = ACPClient(configuration: config)
    }

    public init(client: ACPClient, configuration: ACPConfiguration) {
        self.client = client
        self.configuration = configuration
    }

    public func start() throws {
        try client.start()
    }

    public var processEnvironment: [String: String] {
        configuration.environment
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
