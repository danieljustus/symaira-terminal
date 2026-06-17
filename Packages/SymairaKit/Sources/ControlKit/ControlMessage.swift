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
    public var result: ControlResponseBody?
    public var error: ControlRPCError?
    public var id: Int?

    public init(result: ControlResponseBody, id: Int?) {
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

/// The union of all possible success payloads; exactly one field is non-nil per response.
public struct ControlResponseBody: Codable, Sendable {
    public var snapshot: OrchestrationSnapshot?
    public var panes: [PaneSnapshot]?
    public var worktrees: [WorktreeSnapshot]?
    public var approvals: [ApprovalSummary]?
    public var spawnedPaneID: UUID?
    public var focusedPaneID: UUID?
    public var blockedPaneID: UUID?
    public var ok: Bool?

    public static func of(snapshot: OrchestrationSnapshot) -> Self {
        var b = Self(); b.snapshot = snapshot; return b
    }
    public static func of(panes: [PaneSnapshot]) -> Self {
        var b = Self(); b.panes = panes; return b
    }
    public static func of(worktrees: [WorktreeSnapshot]) -> Self {
        var b = Self(); b.worktrees = worktrees; return b
    }
    public static func of(approvals: [ApprovalSummary]) -> Self {
        var b = Self(); b.approvals = approvals; return b
    }
    public static func spawned(_ id: UUID) -> Self {
        var b = Self(); b.spawnedPaneID = id; return b
    }
    public static func focused(_ id: UUID) -> Self {
        var b = Self(); b.focusedPaneID = id; return b
    }
    public static func blocked(_ id: UUID?) -> Self {
        var b = Self(); b.blockedPaneID = id; return b
    }
    public static var ok: Self {
        var b = Self(); b.ok = true; return b
    }
}

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
