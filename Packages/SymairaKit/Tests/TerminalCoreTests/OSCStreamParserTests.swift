import Foundation
import Testing
@testable import TerminalCore

private func feed(_ parser: inout OSCStreamParser, _ text: String) -> [OSCEvent] {
    parser.feed(Array(text.utf8))
}

@Suite struct OSCStreamParserTests {
    @Test func windowTitleViaBEL() {
        var parser = OSCStreamParser()
        let events = feed(&parser, "noise\u{1B}]0;my title\u{07}more noise")
        #expect(events == [.windowTitle("my title")])
    }

    @Test func windowTitleViaSTTerminator() {
        var parser = OSCStreamParser()
        let events = feed(&parser, "\u{1B}]2;agent pane\u{1B}\\")
        #expect(events == [.windowTitle("agent pane")])
    }

    @Test func workingDirectoryOSC7() {
        var parser = OSCStreamParser()
        let events = feed(&parser, "\u{1B}]7;file://localhost/Users/dev/project\u{07}")
        #expect(events.count == 1)
        guard case let .workingDirectory(url) = events[0] else {
            Issue.record("expected workingDirectory, got \(events)")
            return
        }
        #expect(url.path == "/Users/dev/project")
    }

    @Test func semanticPromptCycle() {
        var parser = OSCStreamParser()
        let stream = "\u{1B}]133;A\u{07}$ \u{1B}]133;B\u{07}make test\u{1B}]133;C\u{07}output…\u{1B}]133;D;2\u{07}"
        let events = feed(&parser, stream)
        #expect(events == [
            .semanticPrompt(.promptStart),
            .semanticPrompt(.commandStart),
            .semanticPrompt(.outputStart),
            .semanticPrompt(.commandEnd(exitCode: 2)),
        ])
    }

    @Test func semanticPromptEndWithoutExitCode() {
        var parser = OSCStreamParser()
        let events = feed(&parser, "\u{1B}]133;D\u{07}")
        #expect(events == [.semanticPrompt(.commandEnd(exitCode: nil))])
    }

    @Test func notificationOSC777() {
        var parser = OSCStreamParser()
        let events = feed(&parser, "\u{1B}]777;notify;Agent-A;Task completed\u{07}")
        #expect(events == [.notification(title: "Agent-A", body: "Task completed")])
    }

    @Test func notificationOSC777BodyMayContainSemicolons() {
        var parser = OSCStreamParser()
        let events = feed(&parser, "\u{1B}]777;notify;T;a;b;c\u{07}")
        #expect(events == [.notification(title: "T", body: "a;b;c")])
    }

    @Test func kittyNotificationOSC99() {
        var parser = OSCStreamParser()
        let events = feed(&parser, "\u{1B}]99;i=1:d=0;Build finished\u{07}")
        #expect(events == [.notification(title: "Build finished", body: "")])
    }

    @Test func sequenceSplitAcrossChunks() {
        var parser = OSCStreamParser()
        var events = feed(&parser, "\u{1B}]133")
        #expect(events.isEmpty)
        events += feed(&parser, ";D;0")
        #expect(events.isEmpty)
        events += feed(&parser, "\u{07}")
        #expect(events == [.semanticPrompt(.commandEnd(exitCode: 0))])
    }

    @Test func splitSTTerminatorAcrossChunks() {
        var parser = OSCStreamParser()
        var events = feed(&parser, "\u{1B}]0;title\u{1B}")
        events += feed(&parser, "\\")
        #expect(events == [.windowTitle("title")])
    }

    @Test func unhandledCodesAreSurfacedNotDropped() {
        var parser = OSCStreamParser()
        let events = feed(&parser, "\u{1B}]52;c;Zm9v\u{07}")
        #expect(events == [.unhandled(code: 52, payload: "c;Zm9v")])
    }

    @Test func oversizedPayloadIsDiscarded() {
        var parser = OSCStreamParser()
        let huge = String(repeating: "x", count: OSCStreamParser.maxPayloadLength + 100)
        let events = feed(&parser, "\u{1B}]0;\(huge)\u{07}\u{1B}]0;ok\u{07}")
        #expect(events == [.windowTitle("ok")])
    }

    @Test func nonOSCEscapeSequencesAreIgnored() {
        var parser = OSCStreamParser()
        let events = feed(&parser, "\u{1B}[31mred\u{1B}[0m\u{1B}]0;t\u{07}")
        #expect(events == [.windowTitle("t")])
    }

    @Test func hyperlinkStartWithBEL() {
        var parser = OSCStreamParser()
        let events = feed(&parser, "\u{1B}]8;id=link1;https://example.com\u{07}")
        #expect(events.count == 1)
        guard case let .hyperlink(uri, params) = events[0] else {
            Issue.record("expected hyperlink, got \(events)")
            return
        }
        #expect(uri?.absoluteString == "https://example.com")
        #expect(params == "id=link1")
    }

    @Test func hyperlinkEndWithST() {
        var parser = OSCStreamParser()
        let events = feed(&parser, "\u{1B}]8;;\u{1B}\\")
        #expect(events.count == 1)
        guard case let .hyperlink(uri, params) = events[0] else {
            Issue.record("expected hyperlink, got \(events)")
            return
        }
        #expect(uri == nil)
        #expect(params.isEmpty)
    }

    @Test func hyperlinkStartEndCycle() {
        var parser = OSCStreamParser()
        let stream = "\u{1B}]8;id=mylink;https://example.com\u{07}click here\u{1B}]8;;\u{07}"
        let events = feed(&parser, stream)
        #expect(events.count == 2)
        guard case let .hyperlink(startURI, startParams) = events[0] else {
            Issue.record("expected hyperlink start, got \(events[0])")
            return
        }
        #expect(startURI?.absoluteString == "https://example.com")
        #expect(startParams == "id=mylink")
        guard case let .hyperlink(endURI, endParams) = events[1] else {
            Issue.record("expected hyperlink end, got \(events[1])")
            return
        }
        #expect(endURI == nil)
        #expect(endParams.isEmpty)
    }

    @Test func hyperlinkEmptyURI() {
        var parser = OSCStreamParser()
        let events = feed(&parser, "\u{1B}]8;id=x;\u{07}")
        #expect(events.count == 1)
        guard case let .hyperlink(uri, params) = events[0] else {
            Issue.record("expected hyperlink, got \(events)")
            return
        }
        #expect(uri == nil)
        #expect(params == "id=x")
    }
}

@Suite struct EnvironmentSanitizerTests {
    @Test func stripsSecretsAndFlagsKeepsTheRest() {
        let env = [
            "PATH": "/usr/bin",
            "HOME": "/Users/dev",
            "ANTHROPIC_API_KEY": "sk-ant-x",
            "OPENAI_API_KEY": "sk-x",
            "OPENROUTER_API_KEY": "sk-or-x",
            "CLAUDECODE": "1",
            "CLAUDE_CODE_ENTRYPOINT": "cli",
            "GEMINI_API_KEY": "g-x",
            "AWS_SECRET_ACCESS_KEY": "key",
            "AZURE_OPENAI_API_KEY": "key",
            "COHERE_API_KEY": "key",
            "HF_TOKEN": "token",
            "TOGETHER_API_KEY": "key",
            "HUGGINGFACE_HUB_TOKEN": "token",
            "TERM": "xterm-256color",
        ]
        let sanitized = EnvironmentSanitizer.sanitize(env)
        #expect(sanitized == [
            "PATH": "/usr/bin",
            "HOME": "/Users/dev",
            "TERM": "xterm-256color",
        ])
    }
}
