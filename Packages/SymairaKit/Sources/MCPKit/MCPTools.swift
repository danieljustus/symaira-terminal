import ControlKit
import Darwin
import Foundation

enum MCPTool: String, CaseIterable {
    case listAgents = "list_agents"
    case readPaneOutput = "read_pane_output"
    case getPendingApprovals = "get_pending_approvals"
    case spawn
    case focus
    case blocked

    var definition: MCPToolDefinition {
        switch self {
        case .listAgents:
            return MCPToolDefinition(
                name: rawValue,
                description: "Returns a list of all current terminal panes with their agent status, "
                    + "title, and working directory. Use this to discover what agents are running.",
                inputSchema: MCPInputSchema(properties: [:], required: []))

        case .readPaneOutput:
            return MCPToolDefinition(
                name: rawValue,
                description: "Returns the last N lines of a terminal pane's scrollback buffer. "
                    + "Use this to inspect command output, build logs, or recent shell history.",
                inputSchema: MCPInputSchema(
                    properties: [
                        "lines": MCPPropertySchema(
                            type: "integer",
                            description: "Maximum number of lines to return (1–10000). Defaults to 200.",
                            default: AnyCodable(200)),
                        "pane_id": MCPPropertySchema(
                            type: "string",
                            description: "UUID of the target pane. Omit to use the currently focused pane.",
                            default: nil)
                    ],
                    required: []))

        case .getPendingApprovals:
            return MCPToolDefinition(
                name: rawValue,
                description: "Returns all pending agent approval requests. Each approval includes "
                    + "the pane ID, agent name, prompt summary, and how long it has been waiting. "
                    + "No approve/deny action is available — approvals are GUI-only.",
                inputSchema: MCPInputSchema(properties: [:], required: []))

        case .spawn:
            return MCPToolDefinition(
                name: rawValue,
                description: "Opens a new terminal pane running the specified agent. Optionally "
                    + "isolates the agent in a git worktree branch.",
                inputSchema: MCPInputSchema(
                    properties: [
                        "agent_id": MCPPropertySchema(
                            type: "string",
                            description: "Agent identifier (e.g. \"claude-code\", \"aider\").",
                            default: nil),
                        "worktree_branch": MCPPropertySchema(
                            type: "string",
                            description: "Branch name for worktree-isolated launch.",
                            default: nil),
                        "working_directory": MCPPropertySchema(
                            type: "string",
                            description: "Working directory for the new pane.",
                            default: nil)
                    ],
                    required: ["agent_id"]))

        case .focus:
            return MCPToolDefinition(
                name: rawValue,
                description: "Selects an existing pane by its UUID, making it the active pane.",
                inputSchema: MCPInputSchema(
                    properties: [
                        "pane_id": MCPPropertySchema(
                            type: "string",
                            description: "UUID of the pane to focus.",
                            default: nil)
                    ],
                    required: ["pane_id"]))

        case .blocked:
            return MCPToolDefinition(
                name: rawValue,
                description: "Returns the UUID of the pane that has been awaiting approval longest. "
                    + "Returns null when no pane is blocked.",
                inputSchema: MCPInputSchema(properties: [:], required: []))
        }
    }
}

struct MCPToolDispatcher: Sendable {
    let provider: any OrchestrationControlProvider

    func call(name: String, arguments: [String: AnyCodable]?) async throws -> MCPResult {
        guard let tool = MCPTool(rawValue: name) else {
            throw MCPDispatchError.unknownTool(name)
        }
        switch tool {
        case .listAgents:
            return try await callListAgents()
        case .readPaneOutput:
            return try await callReadPaneOutput(arguments: arguments)
        case .getPendingApprovals:
            return try await callGetPendingApprovals()
        case .spawn:
            return try await callSpawn(arguments: arguments)
        case .focus:
            return try await callFocus(arguments: arguments)
        case .blocked:
            return try await callBlocked()
        }
    }

    private func callListAgents() async throws -> MCPResult {
        let snapshot = try await provider.snapshot()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        let text = String(data: data, encoding: .utf8) ?? "{}"
        return MCPResult(
            content: [MCPContent(type: "text", text: text)],
            isError: false)
    }

    private func callReadPaneOutput(arguments: [String: AnyCodable]?) async throws -> MCPResult {
        let maxLines = 10_000
        var lines = 200
        if let raw = arguments?["lines"]?.value {
            switch raw {
            case let i as Int:    lines = max(1, min(i, maxLines))
            case let d as Double: lines = max(1, min(Int(d), maxLines))
            default: break
            }
        }
        var paneID: UUID?
        if let raw = arguments?["pane_id"]?.value as? String {
            paneID = UUID(uuidString: raw)
        }

        let result = try await provider.readScrollback(paneID: paneID, lines: lines)
        let text = result.lines.joined(separator: "\n")
        return MCPResult(
            content: [MCPContent(type: "text", text: text.isEmpty ? "(no output)" : text)],
            isError: false)
    }

    private func callGetPendingApprovals() async throws -> MCPResult {
        let approvals = try await provider.pendingApprovals()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(approvals)
        let text = String(data: data, encoding: .utf8) ?? "[]"
        return MCPResult(
            content: [MCPContent(type: "text", text: text)],
            isError: false)
    }

    private func callSpawn(arguments: [String: AnyCodable]?) async throws -> MCPResult {
        guard let agentID = arguments?["agent_id"]?.value as? String, !agentID.isEmpty else {
            throw MCPDispatchError.missingRequired("agent_id")
        }
        var worktreeBranch: String?
        if let raw = arguments?["worktree_branch"]?.value as? String {
            worktreeBranch = raw
        }
        var workingDirectory: String?
        if let raw = arguments?["working_directory"]?.value as? String {
            workingDirectory = raw
        }

        let paneID = try await provider.spawn(
            agentID: agentID,
            worktreeBranch: worktreeBranch,
            workingDirectory: workingDirectory)
        let text = "Spawned pane \(paneID.uuidString) running '\(agentID)'."
        return MCPResult(
            content: [MCPContent(type: "text", text: text)],
            isError: false)
    }

    private func callFocus(arguments: [String: AnyCodable]?) async throws -> MCPResult {
        guard let rawID = arguments?["pane_id"]?.value as? String else {
            throw MCPDispatchError.missingRequired("pane_id")
        }
        guard let paneID = UUID(uuidString: rawID) else {
            return MCPResult(
                content: [MCPContent(type: "text", text: "Invalid UUID: \(rawID)")],
                isError: true)
        }
        try await provider.focus(paneID: paneID)
        let text = "Focused pane \(paneID.uuidString)."
        return MCPResult(
            content: [MCPContent(type: "text", text: text)],
            isError: false)
    }

    private func callBlocked() async throws -> MCPResult {
        let blockedID = try await provider.blocked()
        let text: String
        if let id = blockedID {
            text = "{\"paneID\": \"\(id.uuidString)\"}"
        } else {
            text = "{}"
        }
        return MCPResult(
            content: [MCPContent(type: "text", text: text)],
            isError: false)
    }
}

enum MCPDispatchError: Error, Sendable {
    case unknownTool(String)
    case missingRequired(String)
}
