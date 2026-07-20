import Darwin
import Foundation

public enum UnixSocketServerError: Error, Sendable {
    case socketFailed(errno: Int32)
    case bindFailed(errno: Int32)
    case listenFailed(errno: Int32)
}

private final class ConnectionCounter: @unchecked Sendable {
    private var count: Int = 0
    private let lock = NSLock()

    var current: Int { lock.withLock { count } }
    func increment() -> Int { lock.withLock { count += 1; return count } }
    func decrement() { lock.withLock { count -= 1 } }
}

public final class UnixSocketServer: @unchecked Sendable {

    public let socketPath: String
    private let lock = NSLock()
    private var _serverFD: Int32 = -1
    private let counter = ConnectionCounter()

    private var serverFD: Int32 {
        get { lock.withLock { _serverFD } }
        set { lock.withLock { _serverFD = newValue } }
    }

    public init(socketPath: String) {
        self.socketPath = socketPath
    }

    public func start() throws {
        guard serverFD < 0 else { return }

        try? FileManager.default.removeItem(atPath: socketPath)
        let dir = (socketPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true, attributes: nil)
        Darwin.chmod(dir, 0o700)

        // Tighten the umask around bind() so the socket file never has a
        // window with broader-than-owner permissions between bind() and the
        // explicit chmod() below — bind() creates the filesystem node subject
        // to the process umask, same as open()/mkdir().
        let previousUmask = Darwin.umask(0o077)
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            Darwin.umask(previousUmask)
            throw UnixSocketServerError.socketFailed(errno: errno)
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        withUnsafeMutableBytes(of: &addr.sun_path) { ptr in
            for (i, b) in pathBytes.prefix(ptr.count - 1).enumerated() {
                ptr[i] = UInt8(bitPattern: b)
            }
        }
        let bindResult = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        Darwin.umask(previousUmask)
        guard bindResult == 0 else {
            Darwin.close(fd)
            throw UnixSocketServerError.bindFailed(errno: errno)
        }

        Darwin.chmod(socketPath, 0o600)

        guard Darwin.listen(fd, 16) == 0 else {
            Darwin.close(fd)
            throw UnixSocketServerError.listenFailed(errno: errno)
        }

        serverFD = fd
    }

    public func acceptLoop(
        maxConcurrentConnections: Int = 0,
        handler: @Sendable @escaping (Int32) async -> Void
    ) {
        let fd = serverFD
        guard fd >= 0 else { return }
        // accept(2) blocks; it must live on a dedicated thread, never on the
        // cooperative concurrency pool (pool starvation deadlocks the process).
        // stop() closes the fd, which makes accept return < 0 and ends the thread.
        Thread.detachNewThread { [counter] in
            while true {
                let clientFD = Darwin.accept(fd, nil, nil)
                guard clientFD >= 0 else { break }

                if maxConcurrentConnections > 0 {
                    let n = counter.increment()
                    guard n <= maxConcurrentConnections else {
                        counter.decrement()
                        Darwin.close(clientFD)
                        continue
                    }
                }

                Task.detached {
                    defer {
                        if maxConcurrentConnections > 0 { counter.decrement() }
                    }
                    await handler(clientFD)
                }
            }
        }
    }

    public func stop() {
        let fd = serverFD
        if fd >= 0 {
            Darwin.close(fd)
            serverFD = -1
        }
        try? FileManager.default.removeItem(atPath: socketPath)
    }
}
