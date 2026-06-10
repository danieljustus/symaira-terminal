import TerminalCore

/// Production `TerminalEngine` backed by GhosttyKit (libghostty).
///
/// This target is the ONLY place in the codebase allowed to import GhosttyKit
/// or touch its C API (see ADR-001). The real binding lands with the M0 spike;
/// until then this records the pinned engine metadata.
public enum GhosttyEngineInfo {
    /// Exact pinned libghostty-spm release (Ghostty 1.2.x line). Keep in sync
    /// with Package.swift — upgrades are deliberate, tested steps; never use
    /// floating version ranges for the engine.
    public static let pinnedPackageVersion = "1.2.4"
}
