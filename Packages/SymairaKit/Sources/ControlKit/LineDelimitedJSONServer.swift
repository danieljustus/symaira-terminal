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
/// Runs blocking socket syscalls on a single dedicated reader thread per
/// connection so they never occupy the cooperative Swift Concurrency pool
/// (which would starve it and deadlock) and never depend on GCD worker queues
/// (which can stall when the runner's dispatch/XPC environment is degraded —
/// see issue #347).
///
/// Thread bound: exactly one reader thread per connection, created in
/// `handleConnection` and parked between reads. The previous implementation
/// spawned one `Thread.detachNewThread` per `read` call; the connection loop
/// called it once per received chunk, so a chatty client could create an
/// unbounded number of ~512 KB stack threads (issue #354). The reader thread
/// only issues a read while a continuation is pending, so chunks are never
/// dropped and there is at most one in-flight read per connection.
private final class BlockingSocketIO: @unchecked Sendable {
    private let fd: Int32
    private let maxBytes: Int
    private let condition = NSCondition()
    private var pendingContinuation: CheckedContinuation<Data?, Never>?
    private var threadStarted = false
    private var closed = false

    init(fd: Int32, maxBytes: Int) {
        self.fd = fd
        self.maxBytes = maxBytes
    }

    /// Reads the next chunk from the socket, parking the per-connection
    /// reader thread between reads. Returns nil on EOF, error, or idle
    /// timeout — the caller should then tear the connection down.
    func read() async -> Data? {
        await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            condition.lock()
            if closed {
                condition.unlock()
                cont.resume(returning: nil)
                return
            }
            pendingContinuation = cont
            let shouldStartThread = !threadStarted
            if shouldStartThread { threadStarted = true }
            condition.signal()
            condition.unlock()
            if shouldStartThread {
                Thread.detachNewThread { [weak self] in
                    self?.readerLoop()
                }
            }
        }
    }

    /// Ends the reader loop and releases the parked thread. Call when the
    /// connection is being torn down. Idempotent.
    func close() {
        condition.lock()
        closed = true
        condition.broadcast()
        condition.unlock()
    }

    private func readerLoop() {
        var buf = [UInt8](repeating: 0, count: maxBytes)
        while true {
            guard let cont = nextContinuation() else { return }
            let n = buf.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!, $0.count) }
            let chunk: Data? = n > 0 ? Data(buf.prefix(n)) : nil
            cont.resume(returning: chunk)
            if chunk == nil {
                // EOF, error, or idle timeout: the stream is finished. Mark
                // closed so a straggler read() returns nil instead of parking
                // forever on a thread that has exited.
                condition.lock()
                closed = true
                condition.unlock()
                return
            }
        }
    }

    /// Blocks until a read request is pending or the reader is closed.
    private func nextContinuation() -> CheckedContinuation<Data?, Never>? {
        condition.lock()
        while pendingContinuation == nil && !closed {
            condition.wait()
        }
        let cont = pendingContinuation
        pendingContinuation = nil
        condition.unlock()
        return cont
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

        // One persistent reader thread for this connection's whole lifetime
        // (issue #354): the read loop below would otherwise spawn a detached
        // thread per received chunk.
        let reader = BlockingSocketIO(fd: fd, maxBytes: 4096)
        defer { reader.close() }

        var pending = Data()

        while !Task.isCancelled {
            guard let chunk = await reader.read() else { break }
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
