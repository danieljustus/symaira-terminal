import Foundation
import GhosttyTheme
import TerminalCore

/// Ghostty configuration values that the app surfaces to the user.
public struct GhosttyAppConfig: Equatable, Sendable {
    public var theme: String?
    public var fontFamily: String?
    public var fontSize: Double?
    public var ligaturesEnabled: Bool
    public var configPath: String?

    public init(
        theme: String? = nil,
        fontFamily: String? = nil,
        fontSize: Double? = nil,
        ligaturesEnabled: Bool = true,
        configPath: String? = nil
    ) {
        self.theme = theme
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.ligaturesEnabled = ligaturesEnabled
        self.configPath = configPath
    }

    public static let defaultConfigPath = "~/.config/ghostty/config"

    public var resolvedConfigPath: String {
        configPath ?? Self.defaultConfigPath
    }

    public var configFileExists: Bool {
        let expanded = (resolvedConfigPath as NSString).expandingTildeInPath
        return FileManager.default.fileExists(atPath: expanded)
    }

    public static func parse(from configPath: String? = nil) -> GhosttyAppConfig {
        let resolved = configPath ?? defaultConfigPath
        let path = (resolved as NSString).expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8)
        else {
            return GhosttyAppConfig(configPath: configPath)
        }

        var config = GhosttyAppConfig(configPath: configPath)
        for line in text.components(separatedBy: CharacterSet.newlines) {
            let trimmed = line.trimmingCharacters(in: CharacterSet.whitespaces)
            guard !trimmed.hasPrefix("#"), !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: CharacterSet.whitespaces)
            let value = parts[1].trimmingCharacters(in: CharacterSet.whitespaces)

            switch key {
            case "theme":
                config.theme = value
            case "font-family":
                config.fontFamily = value
            case "font-size":
                config.fontSize = Double(value)
            case "font-feature":
                config.ligaturesEnabled = value != "-liga"
            default:
                break
            }
        }
        return config
    }

    public func resolvedTheme() -> GhosttyThemeDefinition? {
        guard let themeName = theme else { return nil }
        return GhosttyThemeCatalog.theme(named: themeName)
    }

    public static func availableThemes() -> [GhosttyThemeDefinition] {
        GhosttyThemeCatalog.allThemes
    }

    public static func searchThemes(query: String) -> [GhosttyThemeDefinition] {
        GhosttyThemeCatalog.search(query)
    }
}
