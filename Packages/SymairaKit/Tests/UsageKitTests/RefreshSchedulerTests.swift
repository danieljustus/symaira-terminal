import Testing
import Foundation
@testable import UsageKit

@Suite struct IncrementalReadCacheTests {
    @Test func returnsZeroForUnseenPath() async {
        let cache = IncrementalReadCache()
        let offset = await cache.readOffset(for: "/tmp/test.jsonl", currentMtime: Date())
        #expect(offset == 0)
    }

    @Test func returnsStoredOffsetWhenMtimeMatches() async {
        let cache = IncrementalReadCache()
        let mtime = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let path = "/tmp/test.jsonl"
        await cache.setOffset(500, path: path, mtime: mtime)
        let offset = await cache.readOffset(for: path, currentMtime: mtime)
        #expect(offset == 500)
    }

    @Test func resetsToZeroWhenMtimeChanges() async {
        let cache = IncrementalReadCache()
        let path = "/tmp/test.jsonl"
        let oldMtime = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let newMtime = Date(timeIntervalSinceReferenceDate: 2_000_000)
        await cache.setOffset(1234, path: path, mtime: oldMtime)
        let offset = await cache.readOffset(for: path, currentMtime: newMtime)
        #expect(offset == 0)
    }

    @Test func invalidateSinglePath() async {
        let cache = IncrementalReadCache()
        let path = "/tmp/test.jsonl"
        let mtime = Date()
        await cache.setOffset(100, path: path, mtime: mtime)
        await cache.invalidate(path: path)
        let offset = await cache.readOffset(for: path, currentMtime: mtime)
        #expect(offset == 0)
    }

    @Test func invalidateAllResetsEverything() async {
        let cache = IncrementalReadCache()
        let mtime = Date()
        await cache.setOffset(100, path: "/tmp/a.jsonl", mtime: mtime)
        await cache.setOffset(200, path: "/tmp/b.jsonl", mtime: mtime)
        await cache.invalidateAll()
        let a = await cache.readOffset(for: "/tmp/a.jsonl", currentMtime: mtime)
        let b = await cache.readOffset(for: "/tmp/b.jsonl", currentMtime: mtime)
        #expect(a == 0)
        #expect(b == 0)
    }
}

@Suite struct RefreshConfigTests {
    @Test func defaultConfigHasExpectedIntervals() {
        let config = RefreshConfig.default
        #expect(config.foregroundInterval == 30)
        #expect(config.backgroundInterval == 300)
        #expect(config.quotaInterval == 300)
    }

    @Test func customConfigPreservesValues() {
        let config = RefreshConfig(
            foregroundInterval: 10,
            backgroundInterval: 600,
            quotaInterval: 180
        )
        #expect(config.foregroundInterval == 10)
        #expect(config.backgroundInterval == 600)
        #expect(config.quotaInterval == 180)
    }
}
