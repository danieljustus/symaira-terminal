import Foundation
import ControlKit
@testable import MCPKit
import TerminalCore
import Testing

struct StubProvider: OrchestrationControlProvider {
    let scrollbackLines: [String]
    var tabResult: TabRequestResult
    var blockedID: UUID?

    func snapshot() async throws -> OrchestrationSnapshot { OrchestrationSnapshot() }
    func panes() async throws -> [PaneSnapshot] { [] }
    func pendingApprovals() async throws -> [ApprovalSummary] { [] }
    func worktrees() async throws -> [WorktreeSnapshot] { [] }
    func spawn(agentID: String, worktreeBranch: String?, workingDirectory: String?) async throws -> UUID { UUID() }
    func focus(paneID: UUID) async throws {}
    func blocked() async throws -> UUID? { blockedID }

    func readScrollback(paneID: UUID?, lines: Int) async throws -> ScrollbackResult {
        ScrollbackResult(paneID: paneID, lines: Array(scrollbackLines.suffix(lines)))
    }

    func requestOpenTab(command: String) async throws -> TabRequestResult {
        tabResult
    }
}

@Suite("MCPTypes")
struct MCPTypesTests {

    @Test("MCPRequestID decodes Int")
    func requestIDInt() throws {
        let json = #"{"jsonrpc":"2.0","id":42,"method":"ping"}"#
        let req = try JSONDecoder().decode(MCPRequest.self, from: Data(json.utf8))
        guard case .int(let v) = req.id else {
            Issue.record("Expected .int ID")
            return
        }
        #expect(v == 42)
    }

    @Test("MCPRequestID decodes String")
    func requestIDString() throws {
        let json = #"{"jsonrpc":"2.0","id":"abc","method":"tools/list"}"#
        let req = try JSONDecoder().decode(MCPRequest.self, from: Data(json.utf8))
        guard case .string(let v) = req.id else {
            Issue.record("Expected .string ID")
            return
        }
        #expect(v == "abc")
    }

    @Test("MCPResponse round-trips through JSON encoder/decoder")
    func responseRoundTrip() throws {
        let response = MCPResponse(
            id: .int(1),
            result: MCPResult(
                tools: [MCPTool.listAgents.definition]))
        let encoder = JSONEncoder()
        let data = try encoder.encode(response)
        let decoded = try JSONDecoder().decode(MCPResponse.self, from: data)
        #expect(decoded.result?.tools?.count == 1)
        #expect(decoded.result?.tools?.first?.name == "list_agents")
    }
}

@Suite("MCPTool definitions")
struct MCPToolDefinitionTests {

    @Test("All tools expose a non-empty name and description")
    func definitionsAreComplete() {
        for tool in MCPTool.allCases {
            #expect(!tool.definition.name.isEmpty)
            #expect(!tool.definition.description.isEmpty)
        }
    }

    @Test("list_agents has no required parameters")
    func listAgentsSchema() {
        let schema = MCPTool.listAgents.definition.inputSchema
        #expect(schema.required?.isEmpty ?? true)
    }

    @Test("read_pane_output schema has 'lines' and 'pane_id' properties")
    func readPaneOutputSchema() {
        let schema = MCPTool.readPaneOutput.definition.inputSchema
        #expect(schema.properties?["lines"] != nil)
        #expect(schema.properties?["pane_id"] != nil)
    }

    @Test("get_pending_approvals has no required parameters")
    func getPendingApprovalsSchema() {
        let schema = MCPTool.getPendingApprovals.definition.inputSchema
        #expect(schema.required?.isEmpty ?? true)
    }

    @Test("spawn schema requires 'agent_id'")
    func spawnSchema() {
        let schema = MCPTool.spawn.definition.inputSchema
        #expect(schema.properties?["agent_id"] != nil)
        #expect(schema.required?.contains("agent_id") == true)
    }

    @Test("focus schema requires 'pane_id'")
    func focusSchema() {
        let schema = MCPTool.focus.definition.inputSchema
        #expect(schema.properties?["pane_id"] != nil)
        #expect(schema.required?.contains("pane_id") == true)
    }

    @Test("blocked has no required parameters")
    func blockedSchema() {
        let schema = MCPTool.blocked.definition.inputSchema
        #expect(schema.required?.isEmpty ?? true)
    }

    @Test("Exactly 6 tools are registered")
    func toolCount() {
        #expect(MCPTool.allCases.count == 6)
    }
}

@Suite("MCPToolDispatcher")
struct MCPToolDispatcherTests {

    let stub = StubProvider(
        scrollbackLines: ["line1", "line2", "line3"],
        tabResult: TabRequestResult(requestID: UUID(), status: "pending_approval"))

    @Test("list_agents returns snapshot as JSON")
    func listAgentsDispatch() async throws {
        let dispatcher = MCPToolDispatcher(provider: stub)
        let result = try await dispatcher.call(name: "list_agents", arguments: nil)
        #expect(result.content?.first?.type == "text")
        let text = result.content?.first?.text ?? ""
        #expect(text.contains("panes"))
    }

    @Test("read_pane_output returns joined lines as text content")
    func readPaneOutputDispatch() async throws {
        let dispatcher = MCPToolDispatcher(provider: stub)
        let result = try await dispatcher.call(
            name: "read_pane_output",
            arguments: ["lines": AnyCodable(2)])
        #expect(result.content?.first?.type == "text")
        let text = result.content?.first?.text ?? ""
        #expect(text.contains("line2"))
        #expect(text.contains("line3"))
    }

    @Test("read_pane_output with no output returns '(no output)' placeholder")
    func readPaneOutputEmpty() async throws {
        let emptyStub = StubProvider(
            scrollbackLines: [],
            tabResult: TabRequestResult(requestID: UUID(), status: "pending_approval"))
        let dispatcher = MCPToolDispatcher(provider: emptyStub)
        let result = try await dispatcher.call(
            name: "read_pane_output",
            arguments: nil)
        #expect(result.content?.first?.text == "(no output)")
    }

    @Test("get_pending_approvals returns approvals array")
    func getPendingApprovalsDispatch() async throws {
        let dispatcher = MCPToolDispatcher(provider: stub)
        let result = try await dispatcher.call(name: "get_pending_approvals", arguments: nil)
        #expect(result.content?.first?.type == "text")
        let text = result.content?.first?.text ?? ""
        #expect(text.contains("["))
    }

    @Test("spawn returns pane ID on success")
    func spawnDispatch() async throws {
        let dispatcher = MCPToolDispatcher(provider: stub)
        let result = try await dispatcher.call(
            name: "spawn",
            arguments: ["agent_id": AnyCodable("claude-code")])
        #expect(result.content?.first?.type == "text")
        let text = result.content?.first?.text ?? ""
        #expect(text.contains("Spawned pane"))
        #expect(text.contains("claude-code"))
    }

    @Test("spawn throws when agent_id is missing")
    func spawnMissingAgentID() async throws {
        let dispatcher = MCPToolDispatcher(provider: stub)
        await #expect(throws: MCPDispatchError.self) {
            _ = try await dispatcher.call(name: "spawn", arguments: nil)
        }
    }

    @Test("focus returns success on valid UUID")
    func focusDispatch() async throws {
        let targetID = UUID()
        let dispatcher = MCPToolDispatcher(provider: stub)
        let result = try await dispatcher.call(
            name: "focus",
            arguments: ["pane_id": AnyCodable(targetID.uuidString)])
        #expect(result.content?.first?.type == "text")
        let text = result.content?.first?.text ?? ""
        #expect(text.contains("Focused pane"))
    }

    @Test("focus returns error on invalid UUID")
    func focusInvalidUUID() async throws {
        let dispatcher = MCPToolDispatcher(provider: stub)
        let result = try await dispatcher.call(
            name: "focus",
            arguments: ["pane_id": AnyCodable("not-a-uuid")])
        #expect(result.isError == true)
    }

    @Test("focus throws when pane_id is missing")
    func focusMissingPaneID() async throws {
        let dispatcher = MCPToolDispatcher(provider: stub)
        await #expect(throws: MCPDispatchError.self) {
            _ = try await dispatcher.call(name: "focus", arguments: nil)
        }
    }

    @Test("blocked returns empty object when none blocked")
    func blockedNoneBlocked() async throws {
        let dispatcher = MCPToolDispatcher(provider: stub)
        let result = try await dispatcher.call(name: "blocked", arguments: nil)
        let text = result.content?.first?.text ?? ""
        #expect(text == "{}")
    }

    @Test("blocked returns pane ID when one is blocked")
    func blockedOneBlocked() async throws {
        let blockedID = UUID()
        let blockedStub = StubProvider(
            scrollbackLines: [],
            tabResult: TabRequestResult(requestID: UUID(), status: "pending_approval"),
            blockedID: blockedID)
        let dispatcher = MCPToolDispatcher(provider: blockedStub)
        let result = try await dispatcher.call(name: "blocked", arguments: nil)
        let text = result.content?.first?.text ?? ""
        #expect(text.contains(blockedID.uuidString))
    }

    @Test("Unknown tool throws MCPDispatchError")
    func unknownTool() async throws {
        let dispatcher = MCPToolDispatcher(provider: stub)
        await #expect(throws: MCPDispatchError.self) {
            _ = try await dispatcher.call(name: "nonexistent", arguments: nil)
        }
    }
}

@Suite("MCPServer handle() dispatch")
struct MCPServerDispatchTests {

    @Test("initialize returns protocol version and capabilities")
    func initializeReturnsCapabilities() async throws {
        let stub = StubProvider(
            scrollbackLines: [],
            tabResult: TabRequestResult(requestID: UUID(), status: "pending_approval"))
        let request = MCPRequest(
            jsonrpc: "2.0",
            id: .int(1),
            method: "initialize",
            params: nil)
        let server = MCPServer()
        let result = try await server.handleForTest(request: request, dispatcher: MCPToolDispatcher(provider: stub))
        #expect(result.protocolVersion == "2024-11-05")
        #expect(result.capabilities?.tools != nil)
        #expect(result.serverInfo?.name == "symaira-terminal")
    }

    @Test("tools/list returns all tool definitions")
    func toolsList() async throws {
        let stub = StubProvider(
            scrollbackLines: [],
            tabResult: TabRequestResult(requestID: UUID(), status: "pending_approval"))
        let request = MCPRequest(
            jsonrpc: "2.0",
            id: .int(2),
            method: "tools/list",
            params: nil)
        let server = MCPServer()
        let result = try await server.handleForTest(request: request, dispatcher: MCPToolDispatcher(provider: stub))
        let tools = result.tools ?? []
        #expect(tools.count == 6)
        let names = tools.map(\.name)
        #expect(names.contains("list_agents"))
        #expect(names.contains("read_pane_output"))
        #expect(names.contains("get_pending_approvals"))
        #expect(names.contains("spawn"))
        #expect(names.contains("focus"))
        #expect(names.contains("blocked"))
    }

    @Test("ping returns empty result")
    func ping() async throws {
        let stub = StubProvider(
            scrollbackLines: [],
            tabResult: TabRequestResult(requestID: UUID(), status: "pending_approval"))
        let request = MCPRequest(
            jsonrpc: "2.0",
            id: .int(3),
            method: "ping",
            params: nil)
        let server = MCPServer()
        let result = try await server.handleForTest(request: request, dispatcher: MCPToolDispatcher(provider: stub))
        #expect(result.tools == nil)
        #expect(result.content == nil)
    }
}
