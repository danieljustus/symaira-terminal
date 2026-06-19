import Foundation

// MARK: - Request

/// JSON-RPC 2.0 request sent by a control client over the Unix domain socket.
public struct ControlRequest: Codable, Sendable {
    public var jsonrpc: String
    public var method: String
    public var params: ControlParams?
    public var id: Int

    public init(method: ControlMethod, params: ControlParams? = nil, id: Int = 1) {
        self.jsonrpc = "2.0"
        self.method = method.rawValue
        self.params = params
        self.id = id
    }
}

/// Supported control surface methods.
public enum ControlMethod: String, Sendable {
    case snapshot = "control/snapshot"
    case panes = "control/panes"
    case pendingApprovals = "control/pendingApprovals"
    case worktrees = "control/worktrees"
    case spawn = "control/spawn"
    case focus = "control/focus"
    case blocked = "control/blocked"
    case readScrollback = "control/readScrollback"
}

/// Optional parameters carried by write-verb requests.
public struct ControlParams: Codable, Sendable {
    public var agentID: String?
    public var worktreeBranch: String?
    public var workingDirectory: String?
    public var paneID: UUID?

    public init(
        agentID: String? = nil,
        worktreeBranch: String? = nil,
        workingDirectory: String? = nil,
        paneID: UUID? = nil
    ) {
        self.agentID = agentID
        self.worktreeBranch = worktreeBranch
        self.workingDirectory = workingDirectory
        self.paneID = paneID
    }
}

// MARK: - Response

/// JSON-RPC 2.0 response sent back to the client.
public struct ControlResponse: Codable, Sendable {
    public var jsonrpc: String
    public var result: ControlResult?
    public var error: ControlRPCError?
    public var id: Int?

    public init(result: ControlResult, id: Int?) {
        self.jsonrpc = "2.0"
        self.result = result
        self.id = id
    }

    public init(error: ControlRPCError, id: Int?) {
        self.jsonrpc = "2.0"
        self.error = error
        self.id = id
    }
}

/// A typed result from the control surface — exactly one case per response.
/// Invalid states (multiple payloads, or no payload) are unrepresentable.
public enum ControlResult: Sendable {
    case snapshot(OrchestrationSnapshot)
    case panes([PaneSnapshot])
    case worktrees([WorktreeSnapshot])
    case approvals([ApprovalSummary])
    case spawned(UUID)
    case focused(UUID)
    case blocked(UUID?)
    case ok
    case scrollback([String])
}

// MARK: - Codable (wire-compatible with old ControlResponseBody JSON)

extension ControlResult: Codable {

    // Wire-format keys — must match the old struct property names exactly.
    private enum CodingKeys: String, CodingKey {
        case snapshot
        case panes
        case worktrees
        case approvals
        case spawnedPaneID
        case focusedPaneID
        case blockedPaneID
        case ok
        case scrollbackLines
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try container.decodeIfPresent(OrchestrationSnapshot.self, forKey: .snapshot) {
            self = .snapshot(v)
        } else if let v = try container.decodeIfPresent([PaneSnapshot].self, forKey: .panes) {
            self = .panes(v)
        } else if let v = try container.decodeIfPresent([WorktreeSnapshot].self, forKey: .worktrees) {
            self = .worktrees(v)
        } else if let v = try container.decodeIfPresent([ApprovalSummary].self, forKey: .approvals) {
            self = .approvals(v)
        } else if let v = try container.decodeIfPresent(UUID.self, forKey: .spawnedPaneID) {
            self = .spawned(v)
        } else if let v = try container.decodeIfPresent(UUID.self, forKey: .focusedPaneID) {
            self = .focused(v)
        } else if container.contains(.blockedPaneID) {
            let v = try container.decodeIfPresent(UUID.self, forKey: .blockedPaneID)
            self = .blocked(v)
        } else if let v = try container.decodeIfPresent(Bool.self, forKey: .ok), v {
            self = .ok
        } else if let v = try container.decodeIfPresent([String].self, forKey: .scrollbackLines) {
            self = .scrollback(v)
        } else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "No known result field present"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .snapshot(let v): try container.encode(v, forKey: .snapshot)
        case .panes(let v): try container.encode(v, forKey: .panes)
        case .worktrees(let v): try container.encode(v, forKey: .worktrees)
        case .approvals(let v): try container.encode(v, forKey: .approvals)
        case .spawned(let v): try container.encode(v, forKey: .spawnedPaneID)
        case .focused(let v): try container.encode(v, forKey: .focusedPaneID)
        case .blocked(let v): try container.encode(v, forKey: .blockedPaneID)
        case .ok: try container.encode(true, forKey: .ok)
        case .scrollback(let v): try container.encode(v, forKey: .scrollbackLines)
        }
    }
}

// MARK: - Backward-compat typealias

/// Deprecated — use `ControlResult` directly.
public typealias ControlResponseBody = ControlResult

// MARK: - Errors

public struct ControlRPCError: Codable, Error, Sendable {
    public var code: Int
    public var message: String

    public static let parseError = ControlRPCError(code: -32700, message: "Parse error")
    public static let methodNotFound = ControlRPCError(code: -32601, message: "Method not found")
    public static let invalidParams = ControlRPCError(code: -32602, message: "Invalid params")
    public static let internalError = ControlRPCError(code: -32603, message: "Internal error")
    public static let noApp = ControlRPCError(code: -32000, message: "Symaira Terminal is not running")

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}

public enum ControlServerError: Error, Sendable {
    case socketFailed(errno: Int32)
    case bindFailed(errno: Int32)
    case listenFailed(errno: Int32)
    case noRunningInstance
}

public enum ControlClientError: Error, Sendable {
    case notConnected
    case noResponse
    case rpcError(ControlRPCError)
    case connectionRefused
}
