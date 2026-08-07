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
/// Runs blocking socket syscalls on dedicated detached threads so they never
/// occupy the cooperative Swift Concurrency pool (which would starve it and
/// deadlock) and never depend on GCD worker queues (which can stall when the
/// runner's dispatch/XPC environment is degraded — see issue #347).
enum BlockingSocketIO {
    static func read(fd: Int32, maxBytes: Int) async -> Data? {
        await withCheckedContinuation { cont in
            Thread.detachNewThread {
                var buf = [UInt8](repeating: 0, count: maxBytes)
                let n = buf.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!, $0.count) }
                cont.resume(returning: n > 0 ? Data(buf.prefix(n)) : nil)
            }
        }
    }
}

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

        while !Task.isCancelled {
            guard let chunk = await BlockingSocketIO.read(fd: fd, maxBytes: 4096) else { break }
            pending.append(chunk)

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
