import Testing
@testable import AgentKit

@Suite struct AgentStatusEngineTests {
    @Test func higherPrioritySourceWins() {
        var engine = AgentStatusEngine()
        engine.apply(StatusObservation(.running, source: .heuristic))
        engine.apply(StatusObservation(.awaitingApproval, source: .acp))
        #expect(engine.current == .awaitingApproval)
    }

    @Test func heuristicMayNotClearACPApprovalPrompt() {
        var engine = AgentStatusEngine()
        engine.apply(StatusObservation(.awaitingApproval, source: .acp))
        engine.apply(StatusObservation(.running, source: .heuristic))
        #expect(engine.current == .awaitingApproval)
    }

    @Test func anySourceMayLeaveSettledState() {
        var engine = AgentStatusEngine()
        engine.apply(StatusObservation(.done, source: .acp))
        engine.apply(StatusObservation(.running, source: .heuristic))
        #expect(engine.current == .running)
        #expect(engine.currentSource == .heuristic)
    }

    @Test func equalPrioritySourceUpdates() {
        var engine = AgentStatusEngine()
        engine.apply(StatusObservation(.running, source: .osc))
        engine.apply(StatusObservation(.error, source: .osc, detail: "build failed"))
        #expect(engine.current == .error)
        #expect(engine.detail == "build failed")
    }

    @Test func processExitSettlesRegardlessOfSource() {
        var engine = AgentStatusEngine()
        engine.apply(StatusObservation(.awaitingApproval, source: .acp))
        engine.processExited(code: 0)
        #expect(engine.current == .done)
        engine.processExited(code: 3)
        #expect(engine.current == .error)
        #expect(engine.detail == "exit 3")
    }
}

@Suite struct AgentCatalogTests {
    @Test func detectsKnownAgentsByBasename() {
        #expect(AgentCatalog.detect(processName: "/opt/homebrew/bin/opencode")?.id == "opencode")
        #expect(AgentCatalog.detect(processName: "claude")?.id == "claude-code")
        #expect(AgentCatalog.detect(processName: "vim") == nil)
    }

    @Test func lookupReturnsKnownAgentByID() {
        let claude = AgentCatalog.lookup(id: "claude-code")
        #expect(claude != nil)
        #expect(claude?.displayName == "Claude Code")
        #expect(claude?.executableNames == ["claude"])

        let opencode = AgentCatalog.lookup(id: "opencode")
        #expect(opencode != nil)
        #expect(opencode?.supportsACP == true)
    }

    @Test func lookupRejectsUnknownIDs() {
        #expect(AgentCatalog.lookup(id: "unknown-agent") == nil)
        #expect(AgentCatalog.lookup(id: "rm -rf /") == nil)
        #expect(AgentCatalog.lookup(id: "") == nil)
        #expect(AgentCatalog.lookup(id: "claude-code; rm -rf /") == nil)
    }

    @Test func resolveExecutablePathFindsAbsolutePaths() {
        let result = AgentCatalog.resolveExecutablePath(named: "/bin/ls")
        #expect(result == "/bin/ls")
    }

    @Test func resolveExecutablePathRejectsNonexistent() {
        #expect(AgentCatalog.resolveExecutablePath(named: "/nonexistent/path/agent") == nil)
    }

    @Test func resolveExecutablePathRejectsDirectories() {
        #expect(AgentCatalog.resolveExecutablePath(named: "/tmp") == nil)
    }
}
