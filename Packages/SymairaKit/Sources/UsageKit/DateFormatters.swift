import Foundation

extension ISO8601DateFormatter {
    /// Shared instance reused across UsageKit's per-line/per-field parsing.
    /// `ISO8601DateFormatter` is documented thread-safe for concurrent read access,
    /// so a single instance avoids repeated formatter allocation in hot loops.
    nonisolated(unsafe) static let usageKitShared = ISO8601DateFormatter()
}
