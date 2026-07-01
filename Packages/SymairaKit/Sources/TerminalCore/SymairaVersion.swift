import Foundation

/// Single source of truth for the application version string.
///
/// All components that report a version (MCP servers, CLI tools, etc.) should
/// reference `SymairaVersion.current` instead of hardcoding a string.
public enum SymairaVersion {
    /// The current marketing version of Symaira Terminal.
    public static let current = "0.8.3"
}
