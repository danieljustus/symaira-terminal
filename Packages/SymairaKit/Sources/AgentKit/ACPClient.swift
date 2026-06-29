import Foundation
import os.log
import TerminalCore

public struct ACPMessage: Codable {
    public let jsonrpc: String
    public let method: String?
    public let params: [String: AnyCodable]?
    public let result: AnyCodable?
    public let error: ACPError?
    public let id: Int?

    public struct ACPError: Codable {
        public let code: Int
        public let message: String
    }
}

public enum ACPEvent {
    case permissionRequest(id: Int, toolName: String, description: String?)
    case permissionResponse(id: Int, allowed: Bool)
    case toolCall(id: String, name: String, arguments: [String: Any])
    case toolResult(id: String, result: Any)
    case statusChange(status: String)
    case error(code: Int, message: String)
}

public struct ACPConfiguration: Sendable {
    public let executable: URL
    public let arguments: [String]
    public let environment: [String: String]
    public let workingDirectory: URL?

    public init(
        executable: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment ?? EnvironmentSanitizer.sanitizedProcessEnvironment()
        self.workingDirectory = workingDirectory
    }

    public static func withProviderKey(
        executable: URL,
        arguments: [String] = [],
        keyName: String,
        keyValue: String,
        workingDirectory: URL? = nil
    ) -> ACPConfiguration {
        var env = EnvironmentSanitizer.sanitizedProcessEnvironment()
        env[keyName] = keyValue
        return ACPConfiguration(
            executable: executable,
            arguments: arguments,
            environment: env,
            workingDirectory: workingDirectory
        )
    }
}

public final class ACPClient: @unchecked Sendable {
    private let process: Process
    private let stdin: Pipe
    private let stdout: Pipe
    private let stderr: Pipe
    private let lock = NSLock()
    private var requestId = 0
    private var pendingRequests: [Int: (Result<Any?, Error>) -> Void] = [:]
    private var eventHandler: ((ACPEvent) -> Void)?
    private var frameParser = ACPFrameParser()
    private var stderrDrainActive = false

    public init(configuration: ACPConfiguration) {
        self.process = Process()
        self.stdin = Pipe()
        self.stdout = Pipe()
        self.stderr = Pipe()

        process.executableURL = configuration.executable
        process.arguments = configuration.arguments
        process.environment = configuration.environment
        if let cwd = configuration.workingDirectory {
            process.currentDirectoryURL = cwd
        }
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
    }

    public convenience init(executable: URL, arguments: [String] = []) {
        self.init(configuration: ACPConfiguration(executable: executable, arguments: arguments))
    }

    public func start() throws {
        try process.run()
        startReading()
        startStderrDrain()
    }

    public func stop() {
        lock.lock()
        let pending = pendingRequests
        pendingRequests.removeAll()
        stderrDrainActive = false
        lock.unlock()
        stderr.fileHandleForReading.readabilityHandler = nil
        for (_, handler) in pending {
            handler(.failure(CancellationError()))
        }
        process.terminate()
    }

    public func onEvent(_ handler: @escaping (ACPEvent) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        eventHandler = handler
    }

    public func sendRequest(method: String, params: [String: Any] = [:], completion: @escaping (Result<Any?, Error>) -> Void) {
        lock.lock()
        let id = requestId
        requestId += 1
        pendingRequests[id] = completion
        lock.unlock()

        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
            "id": id
        ]

        sendData(message)
    }

    public func sendNotification(method: String, params: [String: Any] = [:]) {
        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params
        ]
        sendData(message)
    }

    public func respond(to requestId: Int, result: Any) {
        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "result": result,
            "id": requestId
        ]
        sendData(message)
    }

    public func respondError(to requestId: Int, code: Int, message: String) {
        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "error": ["code": code, "message": message],
            "id": requestId
        ]
        sendData(message)
    }

    private func sendData(_ data: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        let contentLength = jsonString.utf8.count
        let header = "Content-Length: \(contentLength)\r\n\r\n"
        let fullMessage = header + jsonString

        guard let messageData = fullMessage.data(using: .utf8) else {
            os_log("ACPClient: failed to encode message as UTF-8", log: .default, type: .error)
            return
        }

        lock.lock()
        defer { lock.unlock() }
        stdin.fileHandleForWriting.write(messageData)
    }

    private func startReading() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.readLoop()
        }
    }

    private func startStderrDrain() {
        lock.lock()
        stderrDrainActive = true
        lock.unlock()
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            guard let self else { return }
            self.lock.lock()
            let active = self.stderrDrainActive
            self.lock.unlock()
            guard active else { return }
            if let text = String(data: data, encoding: .utf8) {
                os_log("ACP stderr: %{public}@", log: .default, type: .debug, text)
            }
        }
    }

    private func readLoop() {
        while process.isRunning {
            let chunk = stdout.fileHandleForReading.readData(ofLength: 4096)
            guard !chunk.isEmpty else { break }
            lock.lock()
            frameParser.feed(chunk)
            while let message = frameParser.nextMessage() {
                lock.unlock()
                processMessage(message)
                lock.lock()
            }
            lock.unlock()
        }
        lock.lock()
        while let message = frameParser.nextMessage() {
            lock.unlock()
            processMessage(message)
            lock.lock()
        }
        lock.unlock()
    }

    private func processMessage(_ message: [String: Any]) {
        if let id = message["id"] as? Int, let result = message["result"] {
            lock.lock()
            let handler = pendingRequests.removeValue(forKey: id)
            lock.unlock()
            handler?(.success(result))
        } else if let id = message["id"] as? Int, let error = message["error"] as? [String: Any] {
            lock.lock()
            let handler = pendingRequests.removeValue(forKey: id)
            lock.unlock()
            let code = error["code"] as? Int ?? -1
            let message = error["message"] as? String ?? "Unknown error"
            handler?(.failure(NSError(domain: "ACP", code: code, userInfo: [NSLocalizedDescriptionKey: message])))
        } else if let method = message["method"] as? String {
            handleEvent(method: method, params: message["params"] as? [String: Any] ?? [:], id: message["id"] as? Int)
        }
    }

    private func handleEvent(method: String, params: [String: Any], id: Int?) {
        let event: ACPEvent
        switch method {
        case "permission/request":
            let toolName = params["toolName"] as? String ?? "unknown"
            let description = params["description"] as? String
            event = .permissionRequest(id: id ?? 0, toolName: toolName, description: description)
        case "permission/response":
            let allowed = params["allowed"] as? Bool ?? false
            event = .permissionResponse(id: id ?? 0, allowed: allowed)
        case "tool/call":
            let toolId = params["id"] as? String ?? UUID().uuidString
            let name = params["name"] as? String ?? "unknown"
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            event = .toolCall(id: toolId, name: name, arguments: arguments)
        case "tool/result":
            let toolId = params["id"] as? String ?? "unknown"
            let result = params["result"] ?? NSNull()
            event = .toolResult(id: toolId, result: result)
        case "status/change":
            let status = params["status"] as? String ?? "unknown"
            event = .statusChange(status: status)
        default:
            return
        }
        lock.lock()
        let handler = eventHandler
        lock.unlock()
        handler?(event)
    }
}
