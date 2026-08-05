import Foundation

struct ACPFrameParser {
    private var buffer = Data()
    private let maxContentLength: Int
    private let maxBufferedBytes: Int

    init(maxContentLength: Int = 1024 * 1024) {
        self.maxContentLength = maxContentLength
        // The buffer may legitimately hold one in-flight frame (header + declared
        // body). Bounding it slightly above maxContentLength keeps fragmented
        // frames working while a peer that never sends the header terminator
        // cannot grow memory without limit. Exceeding the bound resets the
        // stream — resyncing by dropping is safe for a child-process peer.
        self.maxBufferedBytes = maxContentLength + 64 * 1024
    }

    mutating func feed(_ data: Data) {
        buffer.append(data)
        if buffer.count > maxBufferedBytes {
            buffer.removeAll()
        }
    }

    mutating func nextMessage() -> [String: Any]? {
        while true {
            guard let headerEndRange = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                return nil
            }
            let headerData = buffer[buffer.startIndex..<headerEndRange.lowerBound]
            guard let header = String(data: headerData, encoding: .utf8) else {
                buffer.removeSubrange(buffer.startIndex..<headerEndRange.upperBound)
                continue
            }
            guard let contentLengthMarker = header.range(of: "Content-Length: ") else {
                buffer.removeSubrange(buffer.startIndex..<headerEndRange.upperBound)
                continue
            }
            let lengthStr = header[contentLengthMarker.upperBound...]
            guard let contentLength = Int(lengthStr.trimmingCharacters(in: .whitespaces)) else {
                buffer.removeSubrange(buffer.startIndex..<headerEndRange.upperBound)
                continue
            }
            guard contentLength > 0, contentLength <= maxContentLength else {
                buffer.removeSubrange(buffer.startIndex..<headerEndRange.upperBound)
                continue
            }
            let bodyStart = buffer.index(headerEndRange.upperBound, offsetBy: contentLength, limitedBy: buffer.endIndex)
            guard let bodyEnd = bodyStart else { return nil }
            let bodyData = buffer[headerEndRange.upperBound..<bodyEnd]
            buffer.removeSubrange(buffer.startIndex..<bodyEnd)
            guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
                continue
            }
            return json
        }
    }

    var isEmpty: Bool { buffer.isEmpty }
}
