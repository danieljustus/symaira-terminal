import Foundation

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

public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else {
            value = NSNull()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else if let string = value as? String {
            try container.encode(string)
        } else if let array = value as? [Any] {
            try container.encode(array.map { AnyCodable($0) })
        } else if let dict = value as? [String: Any] {
            try container.encode(dict.mapValues { AnyCodable($0) })
        }
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

public final class ACPClient: @unchecked Sendable {
    private let process: Process
    private let stdin: Pipe
    private let stdout: Pipe
    private let stderr: Pipe
    private let lock = NSLock()
    private var requestId = 0
    private var pendingRequests: [Int: (Result<Any?, Error>) -> Void] = [:]
    private var eventHandler: ((ACPEvent) -> Void)?

    public init(executable: URL, arguments: [String] = []) {
        self.process = Process()
        self.stdin = Pipe()
        self.stdout = Pipe()
        self.stderr = Pipe()

        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
    }

    public func start() throws {
        try process.run()
        startReading()
    }

    public func stop() {
        lock.lock()
        let pending = pendingRequests
        pendingRequests.removeAll()
        lock.unlock()
        for (_, handler) in pending {
            handler(.failure(CancellationError()))
        }
        process.terminate()
    }

    public func onEvent(_ handler: @escaping (ACPEvent) -> Void) {
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

        lock.lock()
        defer { lock.unlock() }
        stdin.fileHandleForWriting.write(fullMessage.data(using: .utf8)!)
    }

    private func startReading() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.readLoop()
        }
    }

    private func readLoop() {
        var buffer = Data()
        while process.isRunning {
            let chunk = stdout.fileHandleForReading.readData(ofLength: 4096)
            guard !chunk.isEmpty else { break }
            buffer.append(chunk)
            while let message = extractMessage(from: &buffer) {
                processMessage(message)
            }
        }
        while let message = extractMessage(from: &buffer) {
            processMessage(message)
        }
    }

    private func extractMessage(from buffer: inout Data) -> [String: Any]? {
        guard let headerEndRange = buffer.range(of: "\r\n\r\n".data(using: .utf8)!) else {
            return nil
        }
        let headerData = buffer[buffer.startIndex..<headerEndRange.upperBound]
        guard let header = String(data: headerData, encoding: .utf8),
              let contentLengthMarker = header.range(of: "Content-Length: ") else {
            buffer.removeSubrange(buffer.startIndex...headerEndRange.upperBound)
            return nil
        }
        let headerStr = header[contentLengthMarker.upperBound...]
        guard let endOfHeader = headerStr.range(of: "\r\n\r\n") else {
            return nil
        }
        let lengthString = String(headerStr[headerStr.startIndex..<endOfHeader.lowerBound])
        guard let contentLength = Int(lengthString.trimmingCharacters(in: CharacterSet.whitespaces)) else {
            buffer.removeSubrange(buffer.startIndex...headerEndRange.upperBound)
            return nil
        }
        let bodyStart = buffer.index(headerEndRange.upperBound, offsetBy: contentLength, limitedBy: buffer.endIndex)
        guard let bodyEnd = bodyStart else { return nil }
        let bodyData = buffer[headerEndRange.upperBound..<bodyEnd]
        buffer.removeSubrange(buffer.startIndex...bodyEnd)
        guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            return nil
        }
        return json
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
        eventHandler?(event)
    }
}
