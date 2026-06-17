import Foundation

public struct ShellIntegrationManager: Sendable {
    public static let shellSnippets: [String: String] = [
        "zsh": "symaira-zsh-integration.zsh",
        "bash": "symaira-bash-integration.bash",
        "fish": "symaira-fish-integration.fish"
    ]

    public init() {}

    public func snippetPath(for shell: String) -> URL? {
        guard let filename = Self.shellSnippets[shell] else { return nil }
        let bundle = Bundle(for: BundleToken.self)
        return bundle.url(forResource: filename, withExtension: nil)
    }

    public func snippetContent(for shell: String) -> String? {
        guard let path = snippetPath(for: shell) else { return nil }
        return try? String(contentsOf: path, encoding: .utf8)
    }

    public func isShellIntegrationInstalled(for shell: String, in homeDir: URL) -> Bool {
        let rcFile: String
        switch shell {
        case "zsh": rcFile = ".zshrc"
        case "bash": rcFile = ".bashrc"
        case "fish": rcFile = ".config/fish/config.fish"
        default: return false
        }

        let rcPath = homeDir.appendingPathComponent(rcFile)
        guard let content = try? String(contentsOf: rcPath, encoding: .utf8) else { return false }
        return content.contains("symaira") && content.contains("integration")
    }
}

private class BundleToken {}
