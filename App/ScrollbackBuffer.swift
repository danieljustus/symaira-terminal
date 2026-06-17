import Foundation

final class ScrollbackBuffer: @unchecked Sendable {
    private var buffer = Data()
    private var lineOffsets: [Int] = [0]
    private let maxLines: Int
    private let maxBytes: Int
    private let lock = NSLock()
    private var cachedText: String?
    private var cachedBufferCount: Int = 0

    init(maxLines: Int = 10_000, maxBytes: Int = 5_242_880) {
        self.maxLines = maxLines
        self.maxBytes = maxBytes
    }

    func append(_ data: [UInt8]) {
        lock.lock()
        defer { lock.unlock() }
        let offset = buffer.count
        buffer.append(contentsOf: data)
        for i in data.indices where data[i] == UInt8(ascii: "\n") {
            lineOffsets.append(offset + i + 1)
        }
        pruneIfNeeded()
        cachedText = nil
        cachedBufferCount = buffer.count
    }

    func searchText(_ query: String) -> [SearchMatch] {
        lock.lock()
        defer { lock.unlock() }
        guard !query.isEmpty else { return [] }

        if cachedText == nil || cachedBufferCount != buffer.count {
            cachedText = String(data: buffer, encoding: .utf8)
            cachedBufferCount = buffer.count
        }

        guard let text = cachedText else { return [] }

        // Case-insensitive search directly on the cached text — no second
        // full-buffer lowercased copy, and offsets map back to the original
        // string without parallel-index gymnastics.
        var matches: [SearchMatch] = []
        var searchStart = text.startIndex
        var lastByteOffset = 0
        var lastIndex = text.startIndex

        while let range = text.range(of: query, options: [.caseInsensitive], range: searchStart..<text.endIndex) {
            let prefixOffset: Int
            if range.lowerBound == lastIndex {
                prefixOffset = lastByteOffset
            } else {
                prefixOffset = lastByteOffset + text[lastIndex..<range.lowerBound].utf8.count
                lastIndex = range.lowerBound
                lastByteOffset = prefixOffset
            }

            let lineNum = lineNumber(for: prefixOffset)
            let lineStart = text[..<range.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
            let lineEnd = text[range.upperBound...].firstIndex(of: "\n") ?? text.endIndex
            let line = String(text[lineStart..<lineEnd]).trimmingCharacters(in: .whitespaces)

            matches.append(SearchMatch(
                lineNumber: lineNum,
                line: line,
                column: text[lineStart..<range.lowerBound].count,
                length: query.count
            ))

            searchStart = range.upperBound
            if matches.count >= 1000 { break }
        }

        return matches
    }

    private func lineNumber(for byteOffset: Int) -> Int {
        var lo = 0
        var hi = lineOffsets.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lineOffsets[mid] <= byteOffset {
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return lo
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        buffer = Data()
        lineOffsets = [0]
        cachedText = nil
        cachedBufferCount = 0
    }

    var currentText: String? {
        lock.lock()
        defer { lock.unlock() }
        return buffer.isEmpty ? nil : String(data: buffer, encoding: .utf8)
    }

    private func pruneIfNeeded() {
        let lineExcess = lineOffsets.count > maxLines
        let byteExcess = buffer.count > maxBytes
        guard lineExcess || byteExcess else { return }

        // Hysteresis: once a hard cap is exceeded, trim down to ~80% of it instead
        // of exactly to the cap. Trimming to the cap means every subsequent append
        // at capacity recopies the whole buffer; dropping a batch amortizes the
        // O(n) copy across ~20%-of-capacity appends.
        let lineTarget = max(1, maxLines * 4 / 5)
        let byteTarget = max(1, maxBytes * 4 / 5)

        // Determine how many lines to drop to satisfy both constraints.
        var linesToDrop = 0
        if lineExcess {
            linesToDrop = lineOffsets.count - lineTarget
        }
        if byteExcess {
            // Find the earliest line boundary that brings us under byteTarget.
            // We need to drop enough lines so that buffer.count - lineOffsets[dropCount] <= byteTarget,
            // i.e. lineOffsets[dropCount] >= buffer.count - byteTarget.
            let targetOffset = buffer.count - byteTarget
            // Binary search for the first lineOffsets entry >= targetOffset.
            var lo = 0
            var hi = lineOffsets.count - 1
            while lo <= hi {
                let mid = (lo + hi) / 2
                if lineOffsets[mid] < targetOffset {
                    lo = mid + 1
                } else {
                    hi = mid - 1
                }
            }
            // lo is now the index of the first offset >= targetOffset.
            // We need to drop at least `lo` lines (keeping line at index lo as the new first line).
            linesToDrop = max(linesToDrop, lo)
        }

        guard linesToDrop > 0, linesToDrop < lineOffsets.count else { return }
        let cutoffOffset = lineOffsets[linesToDrop]
        buffer = Data(buffer[cutoffOffset...])
        lineOffsets = Array(lineOffsets.dropFirst(linesToDrop))
        for i in lineOffsets.indices {
            lineOffsets[i] -= cutoffOffset
        }
    }
}

struct SearchMatch: Sendable {
    let lineNumber: Int
    let line: String
    let column: Int
    let length: Int
}
