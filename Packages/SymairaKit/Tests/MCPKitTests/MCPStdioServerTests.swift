import Foundation
import ControlKit
@testable import MCPKit
import TerminalCore
import Testing

// MARK: - MCPStdioServer dispatch seam

struct StdioStubProvider: OrchestrationControlProvider {
    func snapshot() async throws -> OrchestrationSnapshot { OrchestrationSnapshot() }
    func panes() async throws -> [PaneSnapshot] { [] }
    func pendingApprovals() async throws -> [ApprovalSummary] { [] }
    func worktrees() async throws -> [WorktreeSnapshot] { [] }
    func spawn(agentID: String, worktreeBranch: String?, workingDirectory: String?) async throws -> UUID { UUID() }
    func focus(paneID: UUID) async throws {}
    func blocked() async throws -> UUID? { nil }
    func readScrollback(paneID: UUID?, lines: Int) async throws -> ScrollbackResult {
        ScrollbackResult(paneID: paneID, lines: [])
    }
    func requestOpenTab(command: String) async throws -> TabRequestResult {
        TabRequestResult(requestID: UUID(), status: "pending_approval")
    }
}

@Suite("MCPStdioServer dispatch")
struct MCPStdioServerDispatchTests {
    private let server = MCPStdioServer()
    private let decoder = JSONDecoder()
    private let dispatcher = MCPToolDispatcher(provider: StdioStubProvider())

    @Test func initializeRequestReturnsCapabilities() async {
        let line = Data(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}"#.utf8)
        let response = await server.dispatch(line: line, decoder: decoder, dispatcher: dispatcher)
        #expect(response.id == .int(1))
        #expect(response.error == nil)
        #expect(response.result?.protocolVersion == "2024-11-05")
        #expect(response.result?.capabilities?.tools != nil)
        #expect(response.result?.serverInfo?.name == "symaira-terminal")
    }

    @Test func pingReturnsEmptyResult() async {
        let line = Data(#"{"jsonrpc":"2.0","id":2,"method":"ping"}"#.utf8)
        let response = await server.dispatch(line: line, decoder: decoder, dispatcher: dispatcher)
        #expect(response.id == .int(2))
        #expect(response.error == nil)
    }

    @Test func toolsListReturnsDefinitions() async {
        let line = Data(#"{"jsonrpc":"2.0","id":3,"method":"tools/list"}"#.utf8)
        let response = await server.dispatch(line: line, decoder: decoder, dispatcher: dispatcher)
        #expect(response.error == nil)
        #expect(response.result?.tools?.count == MCPTool.allCases.count)
    }

    @Test func unknownMethodReturnsError() async {
        let line = Data(#"{"jsonrpc":"2.0","id":4,"method":"bogus/method"}"#.utf8)
        let response = await server.dispatch(line: line, decoder: decoder, dispatcher: dispatcher)
        #expect(response.error?.code == -32601)
        #expect(response.error?.message.contains("bogus/method") == true)
    }

    @Test func malformedJSONReturnsParseError() async {
        let line = Data("{not valid json".utf8)
        let response = await server.dispatch(line: line, decoder: decoder, dispatcher: dispatcher)
        #expect(response.error?.code == -32700)
    }

    @Test func toolsCallMissingNameReturnsInvalidParams() async {
        let line = Data(#"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{}}"#.utf8)
        let response = await server.dispatch(line: line, decoder: decoder, dispatcher: dispatcher)
        #expect(response.error?.code == -32602)
        #expect(response.error?.message.contains("name") == true)
    }

    @Test func emptyLineIsIgnored() async {
        // The stdio loop skips empty lines before dispatching; dispatch itself
        // must treat them as parse errors rather than crashing.
        let line = Data()
        let response = await server.dispatch(line: line, decoder: decoder, dispatcher: dispatcher)
        #expect(response.error?.code == -32700)
    }
}
