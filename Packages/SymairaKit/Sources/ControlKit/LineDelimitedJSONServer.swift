import Darwin
import Foundation

/// Protocol for Unix socket servers that communicate via line-delimited JSON-RPC 2.0.
///
/// Provides a shared `handleConnection` implementation that handles:
/// - Socket lifecycle (close on exit)
/// - Idle timeout via `SO_RCVTIMEO`
/// - Frame size limits
/// - Line-delimited message parsing
///
/// Conforming types only need to implement `dispatch(line:decoder:)` and
/// `makeErrorResponse(message:)`.
public protocol LineDelimitedJSONServer: Sendable {
    var maxFrameSize: Int { get }
    var idleTimeoutSeconds: Int { get }

    associatedtype Response: Encodable & Sendable

    nonisolated func dispatch(line: Data, decoder: JSONDecoder) async -> Response
    nonisolated func makeErrorResponse(message: String) -> Response
}

extension LineDelimitedJSONServer {

    public func handleConnection(
        fd: Int32,
        encoder: JSONEncoder,
        decoder: JSONDecoder
    ) async {
        defer { Darwin.close(fd) }

        var timeout = timeval(tv_sec: idleTimeoutSeconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var pending = Data()
        var buf = [UInt8](repeating: 0, count: 4096)

        while !Task.isCancelled {
            let n = buf.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!, $0.count) }
            guard n > 0 else { break }
            pending.append(contentsOf: buf.prefix(n))

            if pending.count > maxFrameSize {
                let errorResponse = makeErrorResponse(message: "Frame exceeds \(maxFrameSize) byte limit")
                writeResponse(errorResponse, fd: fd, encoder: encoder)
                break
            }

            while let nlIdx = pending.firstIndex(of: 0x0a) {
                let line = Data(pending[pending.startIndex..<nlIdx])
                pending.removeSubrange(pending.startIndex...nlIdx)
                guard !line.isEmpty else { continue }

                let response = await dispatch(line: line, decoder: decoder)
                writeResponse(response, fd: fd, encoder: encoder)
            }
        }
    }

    public func writeResponse(_ response: Response, fd: Int32, encoder: JSONEncoder) {
        guard var data = try? encoder.encode(response) else { return }
        data.append(0x0a)
        data.withUnsafeBytes { _ = Darwin.write(fd, $0.baseAddress!, data.count) }
    }
}
