import Foundation

final class ScrollbackBuffer: @unchecked Sendable {
    private var buffer = Data()
    private let maxLines: Int
    private var lineCount = 0
    private let lock = NSLock()

    init(maxLines: Int = 10_000) {
        self.maxLines = maxLines
    }

    func append(_ data: [UInt8]) {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(contentsOf: data)
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
            let lineNum = text[..<range.lowerBound].components(separatedBy: "\n").count
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

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        buffer = Data()
        lineCount = 0
    }

    var currentText: String? {
        lock.lock()
        defer { lock.unlock() }
        return String(data: buffer, encoding: .utf8)
    }

    private func pruneIfNeeded() {
        guard let text = String(data: buffer, encoding: .utf8) else { return }
        let lines = text.components(separatedBy: "\n")
        if lines.count > maxLines {
            let keep = Array(lines.suffix(maxLines))
            if let newData = keep.joined(separator: "\n").data(using: .utf8) {
                buffer = newData
            }
        }
    }
}

struct SearchMatch: Sendable {
    let lineNumber: Int
    let line: String
    let column: Int
    let length: Int
}
