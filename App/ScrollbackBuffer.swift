import Foundation

final class ScrollbackBuffer: @unchecked Sendable {
    private var buffer = Data()
    private var lineOffsets: [Int] = [0]
    private let maxLines: Int
    private let lock = NSLock()

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
    }

    func searchText(_ query: String) -> [SearchMatch] {
        lock.lock()
        defer { lock.unlock() }
        guard !query.isEmpty, let text = String(data: buffer, encoding: .utf8) else { return [] }

        let lowered = query.lowercased()
        let textLowered = text.lowercased()
        var matches: [SearchMatch] = []
        var searchStart = textLowered.startIndex

        while let range = textLowered.range(of: lowered, range: searchStart..<textLowered.endIndex) {
            let prefix = text[..<range.lowerBound]
            let lineNum = prefix.components(separatedBy: "\n").count
            let lineStart = prefix.lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
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

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        buffer = Data()
        lineOffsets = [0]
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
