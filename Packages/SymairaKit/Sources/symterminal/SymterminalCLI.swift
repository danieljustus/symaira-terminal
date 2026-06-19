import ControlKit
import Foundation

// MARK: - Argument parser

struct CLIArgumentParser {
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
    let requiredValueFlags: Set<String>

    init(
        allowedFlags: [FlagSpec],
        positionalArity: Int,
        requiredValueFlags: Set<String> = []
    ) {
        self.allowedFlags = allowedFlags
        self.positionalArity = positionalArity
        self.requiredValueFlags = requiredValueFlags
    }

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

        for flag in requiredValueFlags where values[flag] == nil {
            throw CLIUsageError.missingValue(flag)
        }

        return ParseResult(positionals: positionals, values: values, booleans: booleans)
    }
}

enum CLIUsageError: Error, CustomStringConvertible {
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

// MARK: - Top-level CLI

struct SymterminalCLI {
    let arguments: [String]

    func run() async {
        let args = arguments

        if args.isEmpty || args.first == "--help" || args.first == "-h" {
            printUsage()
            exit(args.isEmpty ? 1 : 0)
        }

        switch args[0] {
        case "status":
            await StatusCommand(flags: Array(args.dropFirst())).run()
        case "spawn":
            await SpawnCommand(flags: Array(args.dropFirst())).run()
        case "blocked":
            await BlockedCommand(flags: Array(args.dropFirst())).run()
        case "focus":
            await FocusCommand(flags: Array(args.dropFirst())).run()
        default:
            fputs("symterminal: unknown command '\(args[0])'\n", stderr)
            fputs("Run 'symterminal --help' for usage.\n", stderr)
            exit(1)
        }
    }

    private func printUsage() {
        print("""
        Usage: symterminal <command> [options]

        Commands:
          status     Show the orchestration snapshot of the running app
          spawn      Open a new pane running a named agent
          blocked    Report (and focus) the longest-blocked pane
          focus      Select a pane by ID

        Options:
          -h, --help  Show this help message

        Run 'symterminal <command> --help' for more information on a command.
        """)
    }
}

// MARK: - status command

struct StatusCommand {
    let flags: [String]

    private static let parser = CLIArgumentParser(
        allowedFlags: [
            .init("--json"),
            .init("--help"),
            .init("-h")
        ],
        positionalArity: 0
    )

    func run() async {
        let parsed: CLIArgumentParser.ParseResult
        do {
            parsed = try Self.parser.parse(flags)
        } catch {
            fputs("Error: \(error)\n", stderr)
            fputs("Usage: symterminal status [--json]\n", stderr)
            exit(1)
        }

        if parsed.hasFlag("--help") || parsed.hasFlag("-h") {
            printHelp()
            return
        }

        let jsonMode = parsed.hasFlag("--json")
        let client = ControlClient()

        do {
            let snapshot = try await client.snapshot()
            if jsonMode {
                printJSON(snapshot)
            } else {
                printHuman(snapshot)
            }
        } catch ControlClientError.connectionRefused {
            fputs("Error: Symaira Terminal is not running (no listener on control socket).\n", stderr)
            fputs("Start the app and try again.\n", stderr)
            exit(1)
        } catch ControlClientError.rpcError(let err) {
            fputs("Error: \(err.message) (code \(err.code))\n", stderr)
            exit(1)
        } catch {
            fputs("Error: \(error)\n", stderr)
            exit(1)
        }
    }

    // MARK: Output

    private func printJSON(_ snapshot: OrchestrationSnapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot),
              let string = String(data: data, encoding: .utf8) else {
            fputs("Error: failed to encode snapshot as JSON\n", stderr)
            exit(1)
        }
        print(string)
    }

    private func printHuman(_ snapshot: OrchestrationSnapshot) {
        let panes = snapshot.panes
        if panes.isEmpty {
            print("No panes open.")
            return
        }

        print("Symaira Terminal — \(panes.count) pane\(panes.count == 1 ? "" : "s")")
        print(String(repeating: "─", count: 50))

        for pane in panes {
            let marker = pane.isCurrent ? "▶" : " "
            let statusIcon = statusEmoji(pane.agentStatus.rawValue)
            let title = pane.title.isEmpty ? "(untitled)" : pane.title
            let cwd = pane.workingDirectory.map { " [\($0)]" } ?? ""
            print("\(marker) \(statusIcon) \(title)\(cwd)")
            if let detail = pane.agentDetail {
                print("    └─ \(detail)")
            }
        }

        if !snapshot.pendingApprovals.isEmpty {
            print("")
            print("⚠️  \(snapshot.pendingApprovals.count) pane(s) awaiting approval")
            for approval in snapshot.pendingApprovals {
                let waiting = formatDuration(from: approval.waitingSince)
                print("   • \(approval.promptSummary) (waiting \(waiting))")
            }
        }

        if !snapshot.worktrees.isEmpty {
            print("")
            print("Worktrees: \(snapshot.worktrees.map(\.branch).joined(separator: ", "))")
        }
    }

    private func statusEmoji(_ rawValue: String) -> String {
        switch rawValue {
        case "idle": return "◦"
        case "running": return "●"
        case "awaitingApproval": return "⚠"
        case "error": return "✗"
        case "done": return "✓"
        default: return "?"
        }
    }

    private func formatDuration(from date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h \((seconds % 3600) / 60)m"
    }

    // MARK: Help

    private func printHelp() {
        print("""
        Usage: symterminal status [options]

        Show the orchestration snapshot of the running Symaira Terminal instance.
        Connects via the local control socket (see ADR-002).

        Options:
          --json      Output the snapshot as JSON (machine-readable)
          -h, --help  Show this help message

        Exit codes:
          0  Success
          1  Symaira Terminal is not running, or another error occurred

        Examples:
          symterminal status           # human-readable table
          symterminal status --json    # JSON for scripting / status bars
          symterminal status --json | jq '.panes[].agentStatus'
        """)
    }
}

// MARK: - spawn command

struct SpawnCommand {
    let flags: [String]

    private static let parser = CLIArgumentParser(
        allowedFlags: [
            .init("--agent", .value),
            .init("--worktree", .value),
            .init("--cwd", .value),
            .init("--help"),
            .init("-h")
        ],
        positionalArity: 0,
        requiredValueFlags: ["--agent"]
    )

    func run() async {
        let parsed: CLIArgumentParser.ParseResult
        do {
            parsed = try Self.parser.parse(flags)
        } catch {
            fputs("Error: \(error)\n", stderr)
            fputs("Usage: symterminal spawn --agent <id> [--worktree <branch>] [--cwd <path>]\n", stderr)
            exit(1)
        }

        if parsed.hasFlag("--help") || parsed.hasFlag("-h") {
            printHelp(); return
        }

        guard let agentID = parsed.values["--agent"] else {
            fputs("Error: --agent <id> is required.\n", stderr)
            fputs("Run 'symterminal spawn --help' for usage.\n", stderr)
            exit(1)
        }

        let worktree = parsed.values["--worktree"]
        let cwd = parsed.values["--cwd"]
        let client = ControlClient()

        do {
            let paneID = try await client.spawn(
                agentID: agentID, worktreeBranch: worktree, workingDirectory: cwd)
            print("Spawned pane \(paneID) running '\(agentID)'")
        } catch ControlClientError.connectionRefused {
            fputs("Error: Symaira Terminal is not running.\n", stderr); exit(1)
        } catch ControlClientError.rpcError(let err) {
            fputs("Error: \(err.message) (code \(err.code))\n", stderr); exit(1)
        } catch {
            fputs("Error: \(error)\n", stderr); exit(1)
        }
    }

    private func printHelp() {
        print("""
        Usage: symterminal spawn --agent <id> [--worktree <branch>] [--cwd <path>]

        Open a new pane in Symaira Terminal running the named agent.
        The agent process inherits a sanitized environment (no provider secrets).

        Options:
          --agent <id>       Agent command or identifier (required)
          --worktree <branch> Open the pane in the worktree for this branch
          --cwd <path>       Set the working directory for the new pane
          -h, --help         Show this help message

        Examples:
          symterminal spawn --agent claude-code
          symterminal spawn --agent opencode --worktree symaira/task-42
          symterminal spawn --agent aider --cwd /path/to/repo
        """)
    }
}

// MARK: - blocked command

struct BlockedCommand {
    let flags: [String]

    private static let parser = CLIArgumentParser(
        allowedFlags: [
            .init("--json"),
            .init("--help"),
            .init("-h")
        ],
        positionalArity: 0
    )

    func run() async {
        let parsed: CLIArgumentParser.ParseResult
        do {
            parsed = try Self.parser.parse(flags)
        } catch {
            fputs("Error: \(error)\n", stderr)
            fputs("Usage: symterminal blocked [--json]\n", stderr)
            exit(1)
        }

        if parsed.hasFlag("--help") || parsed.hasFlag("-h") {
            printHelp(); return
        }

        let jsonMode = parsed.hasFlag("--json")
        let client = ControlClient()

        do {
            let paneID = try await client.blocked()
            if let id = paneID {
                if jsonMode {
                    print("{\n  \"blockedPaneID\": \"\(id)\"\n}")
                } else {
                    print("Focused longest-blocked pane: \(id)")
                }
            } else {
                if jsonMode {
                    print("{\n  \"blockedPaneID\": null\n}")
                } else {
                    print("No panes are currently blocked.")
                }
            }
        } catch ControlClientError.connectionRefused {
            fputs("Error: Symaira Terminal is not running.\n", stderr); exit(1)
        } catch ControlClientError.rpcError(let err) {
            fputs("Error: \(err.message) (code \(err.code))\n", stderr); exit(1)
        } catch {
            fputs("Error: \(error)\n", stderr); exit(1)
        }
    }

    private func printHelp() {
        print("""
        Usage: symterminal blocked [options]

        Report (and focus in the GUI) the pane that has been awaiting approval
        the longest. Equivalent to Cmd+Shift+U in the app.

        Options:
          --json      Output result as JSON
          -h, --help  Show this help message

        Exit codes:
          0  Success (whether or not a blocked pane was found)
          1  Symaira Terminal is not running, or another error occurred
        """)
    }
}

// MARK: - focus command

struct FocusCommand {
    let flags: [String]

    private static let parser = CLIArgumentParser(
        allowedFlags: [
            .init("--help"),
            .init("-h")
        ],
        positionalArity: 1
    )

    func run() async {
        let parsed: CLIArgumentParser.ParseResult
        do {
            parsed = try Self.parser.parse(flags)
        } catch {
            fputs("Error: \(error)\n", stderr)
            fputs("Usage: symterminal focus <pane-id>\n", stderr)
            exit(1)
        }

        if parsed.hasFlag("--help") || parsed.hasFlag("-h") {
            printHelp(); return
        }

        let paneIDString = parsed.positionals[0]
        guard let paneID = UUID(uuidString: paneIDString) else {
            fputs("Error: '<pane-id>' must be a valid UUID, got '\(paneIDString)'.\n", stderr)
            fputs("Tip: use 'symterminal status --json | jq .panes[].id' to list pane IDs.\n", stderr)
            exit(1)
        }

        let client = ControlClient()

        do {
            try await client.focus(paneID: paneID)
            print("Focused pane \(paneID)")
        } catch ControlClientError.connectionRefused {
            fputs("Error: Symaira Terminal is not running.\n", stderr); exit(1)
        } catch ControlClientError.rpcError(let err) {
            fputs("Error: \(err.message) (code \(err.code))\n", stderr); exit(1)
        } catch {
            fputs("Error: \(error)\n", stderr); exit(1)
        }
    }

    private func printHelp() {
        print("""
        Usage: symterminal focus <pane-id>

        Make the given pane the active (current) pane in Symaira Terminal.
        Use 'symterminal status --json | jq .panes[].id' to list available pane IDs.

        Arguments:
          <pane-id>   UUID of the pane to focus (required)

        Options:
          -h, --help  Show this help message

        Examples:
          symterminal focus 550E8400-E29B-41D4-A716-446655440000
        """)
    }
}
