import Foundation

/// Holds the set of enabled readers and merges their samples into a single snapshot.
///
/// Readers are registered at init time; the registry is immutable after construction
/// to satisfy Swift 6 strict-concurrency requirements. Use `UsageRegistryBuilder`
/// to assemble one.
public struct UsageRegistry: Sendable {
    private let readers: [any UsageReader]

    public init(readers: [any UsageReader]) {
        self.readers = readers
    }

    // MARK: - Reading

    /// Concurrently read all registered readers since `date` and merge the results.
    /// Failures in individual readers are swallowed; the returned snapshot contains
    /// whatever succeeded. Pass a `PartialResultHandler` to observe individual errors.
    public func snapshot(
        since date: Date,
        cache: IncrementalReadCache? = nil,
        onPartialError: (@Sendable (UsageProvider, Error) -> Void)? = nil
    ) async -> UsageSnapshot {
        let now = Date()
        let allSamples = await withTaskGroup(of: [UsageSample].self) { group in
            for reader in readers {
                group.addTask {
                    do {
                        return try await reader.read(since: date, cache: cache)
                    } catch {
                        onPartialError?(reader.provider, error)
                        return []
                    }
                }
            }
            var merged: [UsageSample] = []
            for await batch in group { merged.append(contentsOf: batch) }
            return merged
        }
        return UsageSnapshot(samples: merge(allSamples), generatedAt: now)
    }

    // MARK: - Merge

    /// Deterministic merge: deduplicate by `id`, sort by timestamp ascending.
    public func merge(_ samples: [UsageSample]) -> [UsageSample] {
        var seen = Set<String>()
        var deduped: [UsageSample] = []
        for sample in samples where seen.insert(sample.id).inserted {
            deduped.append(sample)
        }
        return deduped.sorted { $0.timestamp < $1.timestamp }
    }
}
