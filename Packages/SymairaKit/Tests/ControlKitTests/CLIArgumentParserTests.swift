import Testing

// Mirror of CLIArgumentParser from symterminal/SymterminalCLI.swift.
// The symterminal target is an executable and cannot be imported by test targets,
// so we duplicate the pure-logic parser here for unit testing.
private struct CLIArgumentParser {
    enum FlagKind {
        case flag
        case value
    }

    struct FlagSpec {
        let name: String
        let kind: FlagKind

        init(_ name: String, _ kind: FlagKind = .flag) {
            self.name = name
            self.kind = kind
        }
    }

    let allowedFlags: [FlagSpec]
    let positionalArity: Int

    struct ParseResult {
        let positionals: [String]
        let values: [String: String]
        let booleans: Set<String>

        func hasFlag(_ name: String) -> Bool { booleans.contains(name) }
    }

    func parse(_ args: [String]) throws -> ParseResult {
        var positionals: [String] = []
        var values: [String: String] = [:]
        var booleans: Set<String> = []

        var i = 0
        while i < args.count {
            let arg = args[i]

            if arg == "--" {
                i += 1
                while i < args.count {
                    positionals.append(args[i])
                    i += 1
                }
                break
            }

            if arg.hasPrefix("-") {
                guard let spec = allowedFlags.first(where: { $0.name == arg }) else {
                    throw CLIUsageError.unknownFlag(arg)
                }

                switch spec.kind {
                case .flag:
                    booleans.insert(arg)
                case .value:
                    i += 1
                    guard i < args.count else {
                        throw CLIUsageError.missingValue(arg)
                    }
                    guard !args[i].hasPrefix("-") else {
                        throw CLIUsageError.missingValue(arg)
                    }
                    values[arg] = args[i]
                }
            } else {
                positionals.append(arg)
            }

            i += 1
        }

        guard positionals.count == positionalArity else {
            throw CLIUsageError.wrongPositionalArity(
                expected: positionalArity, got: positionals.count)
        }

        return ParseResult(positionals: positionals, values: values, booleans: booleans)
    }
}

private enum CLIUsageError: Error, CustomStringConvertible {
    case unknownFlag(String)
    case missingValue(String)
    case wrongPositionalArity(expected: Int, got: Int)

    var description: String {
        switch self {
        case .unknownFlag(let flag):
            return "unknown option '\(flag)'"
        case .missingValue(let flag):
            return "'\(flag)' requires a value"
        case .wrongPositionalArity(let expected, let got):
            if expected == 0 {
                return "unexpected argument (expected none, got \(got))"
            } else if expected == 1 {
                return "expected exactly 1 argument, got \(got)"
            } else {
                return "expected exactly \(expected) arguments, got \(got)"
            }
        }
    }
}

// MARK: - Parser configuration matching each command

private enum CommandParsers {
    static let status = CLIArgumentParser(
        allowedFlags: [.init("--json"), .init("--help"), .init("-h")],
        positionalArity: 0
    )

    static let spawn = CLIArgumentParser(
        allowedFlags: [
            .init("--agent", .value),
            .init("--worktree", .value),
            .init("--cwd", .value),
            .init("--help"),
            .init("-h")
        ],
        positionalArity: 0
    )

    static let blocked = CLIArgumentParser(
        allowedFlags: [.init("--json"), .init("--help"), .init("-h")],
        positionalArity: 0
    )

    static let focus = CLIArgumentParser(
        allowedFlags: [.init("--help"), .init("-h")],
        positionalArity: 1
    )
}

// MARK: - Tests

@Suite("CLI argument parser")
struct CLIArgumentParserTests {

    // ── status ────────────────────────────────────────────────

    @Test func statusNoFlags() throws {
        let result = try CommandParsers.status.parse([])
        #expect(!result.hasFlag("--json"))
    }

    @Test func statusJsonFlag() throws {
        let result = try CommandParsers.status.parse(["--json"])
        #expect(result.hasFlag("--json"))
    }

    @Test func statusUnknownFlagRejected() throws {
        #expect(throws: CLIUsageError.self) {
            try CommandParsers.status.parse(["--bogus"])
        }
    }

    @Test func statusPositionalRejected() throws {
        #expect(throws: CLIUsageError.self) {
            try CommandParsers.status.parse(["extra"])
        }
    }

    // ── spawn ─────────────────────────────────────────────────

    @Test func spawnAgentWithValidValue() throws {
        let result = try CommandParsers.spawn.parse(["--agent", "claude-code"])
        #expect(result.values["--agent"] == "claude-code")
    }

    @Test func spawnAgentMissingValueBecauseNextIsFlag() throws {
        #expect(throws: CLIUsageError.self) {
            try CommandParsers.spawn.parse(["--agent", "--cwd", "/tmp"])
        }
    }

    @Test func spawnAgentMissingBecauseFlagNotGiven() throws {
        #expect(throws: CLIUsageError.self) {
            try CommandParsers.spawn.parse(["--cwd", "/tmp"])
        }
    }

    @Test func spawnAgentMissingBecauseEmpty() throws {
        #expect(throws: CLIUsageError.self) {
            try CommandParsers.spawn.parse([])
        }
    }

    @Test func spawnAllFlags() throws {
        let result = try CommandParsers.spawn.parse([
            "--agent", "opencode",
            "--worktree", "symaira/task-1",
            "--cwd", "/tmp/repo"
        ])
        #expect(result.values["--agent"] == "opencode")
        #expect(result.values["--worktree"] == "symaira/task-1")
        #expect(result.values["--cwd"] == "/tmp/repo")
    }

    @Test func spawnUnknownFlagRejected() throws {
        #expect(throws: CLIUsageError.self) {
            try CommandParsers.spawn.parse(["--agent", "x", "--bogus"])
        }
    }

    @Test func spawnAgentTrailingFlag() throws {
        #expect(throws: CLIUsageError.self) {
            try CommandParsers.spawn.parse(["--agent"])
        }
    }

    // ── blocked ───────────────────────────────────────────────

    @Test func blockedNoFlags() throws {
        let result = try CommandParsers.blocked.parse([])
        #expect(!result.hasFlag("--json"))
    }

    @Test func blockedUnknownFlagRejected() throws {
        #expect(throws: CLIUsageError.self) {
            try CommandParsers.blocked.parse(["--verbose"])
        }
    }

    // ── focus ─────────────────────────────────────────────────

    @Test func focusValidUUID() throws {
        let uuid = "550E8400-E29B-41D4-A716-446655440000"
        let result = try CommandParsers.focus.parse([uuid])
        #expect(result.positionals == [uuid])
    }

    @Test func focusExtraPositionalRejected() throws {
        let uuid = "550E8400-E29B-41D4-A716-446655440000"
        #expect(throws: CLIUsageError.self) {
            try CommandParsers.focus.parse([uuid, "extra"])
        }
    }

    @Test func focusNoPositionalRejected() throws {
        #expect(throws: CLIUsageError.self) {
            try CommandParsers.focus.parse([])
        }
    }

    @Test func focusUnknownFlagRejected() throws {
        let uuid = "550E8400-E29B-41D4-A716-446655440000"
        #expect(throws: CLIUsageError.self) {
            try CommandParsers.focus.parse([uuid, "--bogus"])
        }
    }

    // ── edge cases ────────────────────────────────────────────

    @Test func doubleDashSeparator() throws {
        let result = try CommandParsers.status.parse(["--json", "--", "oops"])
        #expect(result.hasFlag("--json"))
        #expect(result.positionals == ["oops"])
    }

    @Test func flagValueCannotBeAnotherFlag() throws {
        #expect(throws: CLIUsageError.self) {
            try CommandParsers.spawn.parse(["--agent", "--worktree"])
        }
    }

    @Test func errorMessagesAreDescriptive() throws {
        do {
            try CommandParsers.status.parse(["--bogus"])
            Issue.record("Expected error")
        } catch let error as CLIUsageError {
            #expect(error.description.contains("--bogus"))
        }

        do {
            try CommandParsers.spawn.parse(["--agent", "--cwd", "/tmp"])
            Issue.record("Expected error")
        } catch let error as CLIUsageError {
            #expect(error.description.contains("--agent"))
        }

        do {
            try CommandParsers.focus.parse(["uuid", "extra"])
            Issue.record("Expected error")
        } catch let error as CLIUsageError {
            #expect(error.description.contains("1"))
            #expect(error.description.contains("2"))
        }
    }
}
