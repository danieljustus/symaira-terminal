import Foundation
import GhosttyKit
import GhosttyTerminal
import GhosttyTheme

/// Prepares the user's `~/.config/ghostty/config` for the bundled libghostty.
///
/// The bundled engine ships without Ghostty's built-in theme files, so a line
/// like `theme = Catppuccin Latte` — which real Ghostty resolves from its
/// resources — produces a config diagnostic here, and libghostty-spm discards
/// the ENTIRE config on any diagnostic. To keep the rest of the user's config
/// alive, the theme line is stripped and resolved against the GhosttyTheme
/// catalog instead. Theme names that exist as files under
/// `~/.config/ghostty/themes/` are left in place; ghostty loads those itself.
enum GhosttyUserConfig {
    struct Prepared {
        var contents: String
        var theme: TerminalTheme?
    }

    static func prepare(
        contents: String,
        userThemeDirectory: String = ("~/.config/ghostty/themes" as NSString).expandingTildeInPath
    ) -> Prepared {
        guard let themeValue = lastThemeValue(in: contents) else {
            return Prepared(contents: contents, theme: nil)
        }

        let names = themeNames(from: themeValue)
        let allResolvableByGhostty = [names.light, names.dark].allSatisfy { name in
            FileManager.default.fileExists(
                atPath: (userThemeDirectory as NSString).appendingPathComponent(name)
            )
        }
        if allResolvableByGhostty {
            return Prepared(contents: contents, theme: nil)
        }

        let lightDefinition = GhosttyThemeCatalog.theme(named: names.light)
        let darkDefinition = GhosttyThemeCatalog.theme(named: names.dark)
        for (name, definition) in [(names.light, lightDefinition), (names.dark, darkDefinition)]
            where definition == nil {
            NSLog("symaira: ghostty theme \"%@\" not found in catalog, using engine default", name)
        }

        var theme: TerminalTheme?
        if lightDefinition != nil || darkDefinition != nil {
            theme = TerminalTheme(
                light: lightDefinition?.toTerminalConfiguration() ?? .init(),
                dark: darkDefinition?.toTerminalConfiguration() ?? .init()
            )
        }
        return Prepared(contents: strippingThemeLines(from: contents), theme: theme)
    }

    /// Ghostty semantics: the last occurrence of a key wins.
    static func lastThemeValue(in contents: String) -> String? {
        var value: String?
        for line in contents.components(separatedBy: .newlines) {
            guard let (key, lineValue) = parseLine(line), key == "theme" else { continue }
            value = lineValue
        }
        return value
    }

    /// A theme value is either a single name (used for both appearances) or
    /// comma-separated `light:Name` / `dark:Name` entries.
    static func themeNames(from value: String) -> (light: String, dark: String) {
        var light = value
        var dark = value
        for entry in value.split(separator: ",") {
            let trimmed = entry.trimmingCharacters(in: .whitespaces)
            if let name = trimmed.removingCaseInsensitivePrefix("light:") {
                light = name
            } else if let name = trimmed.removingCaseInsensitivePrefix("dark:") {
                dark = name
            }
        }
        return (light.trimmingCharacters(in: .whitespaces), dark.trimmingCharacters(in: .whitespaces))
    }

    static func strippingThemeLines(from contents: String) -> String {
        contents
            .components(separatedBy: .newlines)
            .filter { parseLine($0)?.key != "theme" }
            .joined(separator: "\n")
    }

    /// Diagnostics ghostty reports for the given config contents. libghostty-spm
    /// silently swaps in its default config when the user config has any
    /// diagnostic, so the engine runs this to at least tell the user. Requires
    /// the ghostty runtime to be initialized — call only after the first
    /// `TerminalController` exists.
    @MainActor
    static func diagnostics(for contents: String) -> [String] {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("symaira-config-check-\(UUID().uuidString).conf")
        guard (try? contents.write(to: url, atomically: true, encoding: .utf8)) != nil else {
            return []
        }
        defer { try? FileManager.default.removeItem(at: url) }

        guard let config = ghostty_config_new() else { return [] }
        defer { ghostty_config_free(config) }
        ghostty_config_load_file(config, url.path)
        ghostty_config_finalize(config)

        let count = ghostty_config_diagnostics_count(config)
        guard count > 0 else { return [] }
        return (0 ..< count).compactMap { index in
            let diagnostic = ghostty_config_get_diagnostic(config, index)
            guard let message = diagnostic.message else { return nil }
            return String(cString: message)
        }
    }

    private static func parseLine(_ line: String) -> (key: String, value: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
        let parts = trimmed.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return (
            parts[0].trimmingCharacters(in: .whitespaces),
            parts[1].trimmingCharacters(in: .whitespaces)
        )
    }
}

private extension String {
    func removingCaseInsensitivePrefix(_ prefix: String) -> String? {
        guard lowercased().hasPrefix(prefix.lowercased()) else { return nil }
        return String(dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }
}
