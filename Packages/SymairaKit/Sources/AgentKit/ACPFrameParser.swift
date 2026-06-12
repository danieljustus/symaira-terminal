import Foundation

struct ACPFrameParser {
    private var buffer = Data()
    private let maxContentLength: Int

    init(maxContentLength: Int = 1024 * 1024) {
        self.maxContentLength = maxContentLength
    }

    mutating func feed(_ data: Data) {
        buffer.append(data)
    }

    mutating func nextMessage() -> [String: Any]? {
        while true {
            guard let headerEndRange = buffer.range(of: "\r\n\r\n".data(using: .utf8)!) else {
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
