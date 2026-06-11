import Foundation

final class ScrollbackBuffer: @unchecked Sendable {
    private var buffer = Data()
    private var lineOffsets: [Int] = [0]
    private let maxLines: Int
    private let lock = NSLock()
    private var cachedText: String?
    private var cachedTextLowered: String?
    private var cachedBufferCount: Int = 0

    init(maxLines: Int = 10_000) {
        self.maxLines = maxLines
    }

    func append(_ data: [UInt8]) {
        lock.lock()
        defer { lock.unlock() }
        let offset = buffer.count
        buffer.append(contentsOf: data)
        for i in data.indices {
            if data[i] == UInt8(ascii: "\n") {
                lineOffsets.append(offset + i + 1)
            }
        }
        pruneIfNeeded()
        cachedText = nil
        cachedTextLowered = nil
        cachedBufferCount = buffer.count
    }

    func searchText(_ query: String) -> [SearchMatch] {
        lock.lock()
        defer { lock.unlock() }
        guard !query.isEmpty else { return [] }

        if cachedText == nil || cachedBufferCount != buffer.count {
            cachedText = String(data: buffer, encoding: .utf8)
            cachedTextLowered = cachedText?.lowercased()
        }

        guard let text = cachedText, let textLowered = cachedTextLowered else { return [] }

        let lowered = query.lowercased()
        var matches: [SearchMatch] = []
        var searchStart = textLowered.startIndex

        while let range = textLowered.range(of: lowered, range: searchStart..<textLowered.endIndex) {
            let prefixOffset = text[..<range.lowerBound].utf8.count
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
        cachedTextLowered = nil
        cachedBufferCount = 0
    }

    var currentText: String? {
        lock.lock()
        defer { lock.unlock() }
        return String(data: buffer, encoding: .utf8)
    }

    private func pruneIfNeeded() {
        guard lineOffsets.count > maxLines else { return }
        let excess = lineOffsets.count - maxLines
        let cutoffOffset = lineOffsets[excess]
        buffer = Data(buffer[cutoffOffset...])
        lineOffsets = Array(lineOffsets.dropFirst(excess))
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
