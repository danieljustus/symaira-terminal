import Foundation
import XCTest
@testable import AgentKit

private final class CallbackBox<Value>: @unchecked Sendable {
    var value: Value?
}

final class ACPClientTests: XCTestCase {
    func testRequestCompletesFromChildResponse() throws {
        let client = makeClient(frames: [try responseFrame(result: ["ok": true])])
        let resultBox = CallbackBox<Result<Any?, Error>>()
        let completed = expectation(description: "request completed")

        try client.start()
        client.sendRequest(method: "initialize") { result in
            resultBox.value = result
            completed.fulfill()
        }

        wait(for: [completed], timeout: 2)
        client.stop()

        guard case .success(let result) = resultBox.value else {
            return XCTFail("expected a successful response, got \(String(describing: resultBox.value))")
        }
        let payload = result as? [String: Any]
        XCTAssertEqual(payload?["ok"] as? Bool, true)
    }

    func testDispatchesEventsAndRequestErrors() throws {
        let event = #"{"jsonrpc":"2.0","method":"status/change","params":{"status":"working"}}"#
        let error = #"{"jsonrpc":"2.0","id":0,"error":{"code":-32001,"message":"denied"}}"#
        let client = makeClient(frames: [frame(body: event), frame(body: error)])
        let eventBox = CallbackBox<ACPEvent>()
        let resultBox = CallbackBox<Result<Any?, Error>>()
        let completed = expectation(description: "request completed")
        client.onEvent { eventBox.value = $0 }

        try client.start()
        client.sendRequest(method: "run") { result in
            resultBox.value = result
            completed.fulfill()
        }

        wait(for: [completed], timeout: 2)
        client.stop()

        guard case .statusChange(let status) = eventBox.value else {
            return XCTFail("expected status event, got \(String(describing: eventBox.value))")
        }
        XCTAssertEqual(status, "working")

        guard case .failure(let error as NSError) = resultBox.value else {
            return XCTFail("expected request failure, got \(String(describing: resultBox.value))")
        }
        XCTAssertEqual(error.code, -32001)
        XCTAssertEqual(error.localizedDescription, "denied")
    }

    func testStopFailsPendingRequests() throws {
        let client = makeClient(script: "sleep 2")
        let resultBox = CallbackBox<Result<Any?, Error>>()
        let completed = expectation(description: "pending request cancelled")

        try client.start()
        client.sendRequest(method: "wait") { result in
            resultBox.value = result
            completed.fulfill()
        }
        client.stop()

        wait(for: [completed], timeout: 1)
        guard case .failure = resultBox.value else {
            return XCTFail("expected cancellation, got \(String(describing: resultBox.value))")
        }
    }

    private func makeClient(frames: [String]) -> ACPClient {
        makeClient(script: "printf '%s' \"$1\"; sleep 1", argument: frames.joined())
    }

    private func makeClient(script: String, argument: String = "") -> ACPClient {
        ACPClient(configuration: ACPConfiguration(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script, "acp-test", argument],
            environment: ["PATH": "/usr/bin:/bin"]
        ))
    }

    private func responseFrame(result: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "id": 0,
            "result": result
        ])
        guard let body = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return frame(body: body)
    }

    private func frame(body: String) -> String {
        "Content-Length: \(body.utf8.count)\r\n\r\n\(body)"
    }
}
