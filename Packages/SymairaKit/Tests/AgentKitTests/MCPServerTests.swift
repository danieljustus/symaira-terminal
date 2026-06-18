import XCTest
import AgentKit

final class MockMCPDelegate: TerminalMCPDelegate, @unchecked Sendable {
    var activeScrollback = "line 1\nline 2\nline 3"
    var lastScrollbackLinesAsked: Int?
    var openTabCommandCalled: String?
    var openTabResult = true

    func getActiveScrollback(lines: Int) async -> String {
        lastScrollbackLinesAsked = lines
        return activeScrollback
    }

    func openTab(command: String) async -> Bool {
        openTabCommandCalled = command
        return openTabResult
    }
}

final class MCPServerTests: XCTestCase {
    func testServerInitialization() async throws {
        let delegate = MockMCPDelegate()
        let server = try MCPServer(port: 8889, delegate: delegate)
        server.start()
        defer { server.stop() }

        let initRequest: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "initialize",
            "id": 1,
            "params": [
                "protocolVersion": "2024-11-05"
            ]
        ]

        let response = try await sendPostRequest(port: 8889, body: initRequest)
        XCTAssertEqual(response["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(response["id"] as? Int, 1)
        let result = response["result"] as? [String: Any]
        XCTAssertNotNil(result)
        XCTAssertEqual(result?["protocolVersion"] as? String, "2024-11-05")

        let serverInfo = result?["serverInfo"] as? [String: Any]
        XCTAssertEqual(serverInfo?["name"] as? String, "symaira-terminal")
    }

    func testListTools() async throws {
        let delegate = MockMCPDelegate()
        let server = try MCPServer(port: 8889, delegate: delegate)
        server.start()
        defer { server.stop() }

        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "tools/list",
            "id": 2
        ]

        let response = try await sendPostRequest(port: 8889, body: request)
        XCTAssertEqual(response["id"] as? Int, 2)
        let result = response["result"] as? [String: Any]
        let tools = result?["tools"] as? [[String: Any]]
        XCTAssertNotNil(tools)
        XCTAssertEqual(tools?.count, 2)
        XCTAssertEqual(tools?[0]["name"] as? String, "read_scrollback")
        XCTAssertEqual(tools?[1]["name"] as? String, "open_tab")
    }

    func testCallReadScrollback() async throws {
        let delegate = MockMCPDelegate()
        let server = try MCPServer(port: 8889, delegate: delegate)
        server.start()
        defer { server.stop() }

        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "tools/call",
            "id": 3,
            "params": [
                "name": "read_scrollback",
                "arguments": [
                    "lines": 2
                ]
            ]
        ]

        let response = try await sendPostRequest(port: 8889, body: request)
        XCTAssertEqual(response["id"] as? Int, 3)
        let result = response["result"] as? [String: Any]
        let content = result?["content"] as? [[String: Any]]
        XCTAssertEqual(content?[0]["type"] as? String, "text")
        XCTAssertEqual(content?[0]["text"] as? String, "line 1\nline 2\nline 3")
        XCTAssertEqual(delegate.lastScrollbackLinesAsked, 2)
    }

    func testCallOpenTab() async throws {
        let delegate = MockMCPDelegate()
        let server = try MCPServer(port: 8889, delegate: delegate)
        server.start()
        defer { server.stop() }

        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "tools/call",
            "id": 4,
            "params": [
                "name": "open_tab",
                "arguments": [
                    "command": "echo hello"
                ]
            ]
        ]

        let response = try await sendPostRequest(port: 8889, body: request)
        XCTAssertEqual(response["id"] as? Int, 4)
        let result = response["result"] as? [String: Any]
        let content = result?["content"] as? [[String: Any]]
        XCTAssertEqual(content?[0]["type"] as? String, "text")
        XCTAssertTrue((content?[0]["text"] as? String)?.contains("echo hello") == true)
        XCTAssertEqual(delegate.openTabCommandCalled, "echo hello")
    }

    private func sendPostRequest(port: UInt16, body: [String: Any]) async throws -> [String: Any] {
        let url = URL(string: "http://127.0.0.1:\(port)/")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json ?? [:]
    }
}
