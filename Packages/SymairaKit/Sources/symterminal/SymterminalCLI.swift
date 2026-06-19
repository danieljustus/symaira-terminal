import ControlKit
import Foundation
import MCPKit

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
        case "mcp":
            await MCPCommand(flags: Array(args.dropFirst())).run()
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
          status               Show the orchestration snapshot of the running app
          spawn --agent <id>   Open a new pane running the named agent
          blocked              Report (and focus) the longest-blocked agent
          focus <pane-id>      Select an existing pane by its UUID
          mcp                  Start an MCP server over stdio (for AI agent integration)

        Options:
          -h, --help  Show this help message

        Run 'symterminal <command> --help' for more information on a command.
        """)
    }
}

// MARK: - status command

struct StatusCommand {
    let flags: [String]

    func run() async {
        if flags.contains("--help") || flags.contains("-h") {
            printHelp()
            return
        }

        let jsonMode = flags.contains("--json")
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

    func run() async {
        if flags.contains("--help") || flags.contains("-h") {
            printHelp()
            return
        }

        guard let agentIndex = flags.firstIndex(of: "--agent"),
              agentIndex + 1 < flags.count else {
            fputs("Error: --agent <id> is required.\n", stderr)
            fputs("Run 'symterminal spawn --help' for usage.\n", stderr)
            exit(1)
        }
        let agentID = flags[agentIndex + 1]

        var worktreeBranch: String?
        if let branchIndex = flags.firstIndex(of: "--worktree"),
           branchIndex + 1 < flags.count {
            worktreeBranch = flags[branchIndex + 1]
        }

        var workingDirectory: String?
        if let cwdIndex = flags.firstIndex(of: "--cwd"),
           cwdIndex + 1 < flags.count {
            workingDirectory = flags[cwdIndex + 1]
        }

        let jsonMode = flags.contains("--json")
        let client = ControlClient()

        do {
            let paneID = try await client.spawn(
                agentID: agentID,
                worktreeBranch: worktreeBranch,
                workingDirectory: workingDirectory)
            if jsonMode {
                let result: [String: String] = [
                    "paneID": paneID.uuidString,
                    "agentID": agentID
                ]
                let data = try JSONSerialization.data(
                    withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                print(String(data: data, encoding: .utf8)!)
            } else {
                print("Spawned pane \(paneID.uuidString) running '\(agentID)'.")
                if let branch = worktreeBranch {
                    print("Worktree branch: \(branch)")
                }
                if let cwd = workingDirectory {
                    print("Working directory: \(cwd)")
                }
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

    private func printHelp() {
        print("""
        Usage: symterminal spawn --agent <id> [options]

        Open a new terminal pane running the named agent, optionally in an
        isolated git worktree.

        Options:
          --agent <id>        Agent identifier (required, e.g. "claude-code")
          --worktree <branch> Branch name for worktree-isolated launch
          --cwd <path>        Working directory for the new pane
          --json              Output the result as JSON
          -h, --help          Show this help message

        Exit codes:
          0  Success — pane created
          1  Error (app not running, missing params, invalid agent)

        Examples:
          symterminal spawn --agent claude-code
          symterminal spawn --agent aider --worktree symaira/task-1 --cwd ~/project
          symterminal spawn --agent open-code --json | jq '.paneID'
        """)
    }
}

// MARK: - blocked command

struct BlockedCommand {
    let flags: [String]

    func run() async {
        if flags.contains("--help") || flags.contains("-h") {
            printHelp()
            return
        }

        let jsonMode = flags.contains("--json")
        let client = ControlClient()

        do {
            let blockedID = try await client.blocked()
            if jsonMode {
                if let id = blockedID {
                    let result: [String: String] = ["paneID": id.uuidString]
                    let data = try JSONSerialization.data(
                        withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                    print(String(data: data, encoding: .utf8)!)
                } else {
                    print("{}")
                }
            } else {
                if let id = blockedID {
                    print("Longest-blocked pane: \(id.uuidString)")
                    print("(Pane has been focused.)")
                } else {
                    print("No panes are currently blocked.")
                }
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

    private func printHelp() {
        print("""
        Usage: symterminal blocked [options]

        Report the pane that has been awaiting approval longest, and focus it.
        Exits cleanly with a message when no pane is blocked.

        Options:
          --json    Output the result as JSON (pane ID or empty object)
          -h, --help  Show this help message

        Exit codes:
          0  Success (blocked pane found, or no panes blocked)
          1  Symaira Terminal is not running, or another error occurred

        Examples:
          symterminal blocked           # focus longest-blocked agent
          symterminal blocked --json    # JSON output for scripting
        """)
    }
}

// MARK: - focus command

struct FocusCommand {
    let flags: [String]

    func run() async {
        if flags.contains("--help") || flags.contains("-h") {
            printHelp()
            return
        }

        // The pane ID is the first positional argument (not prefixed with --)
        guard let paneArg = flags.first, !paneArg.hasPrefix("-") else {
            fputs("Error: <pane-id> is required.\n", stderr)
            fputs("Run 'symterminal focus --help' for usage.\n", stderr)
            exit(1)
        }

        guard let paneID = UUID(uuidString: paneArg) else {
            fputs("Error: '\(paneArg)' is not a valid UUID.\n", stderr)
            exit(1)
        }

        let jsonMode = flags.contains("--json")
        let client = ControlClient()

        do {
            try await client.focus(paneID: paneID)
            if jsonMode {
                let result: [String: String] = ["paneID": paneID.uuidString]
                let data = try JSONSerialization.data(
                    withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                print(String(data: data, encoding: .utf8)!)
            } else {
                print("Focused pane \(paneID.uuidString).")
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

    private func printHelp() {
        print("""
        Usage: symterminal focus <pane-id> [options]

        Select an existing pane by its UUID, making it the active pane.

        Options:
          --json    Output the result as JSON
          -h, --help  Show this help message

        Exit codes:
          0  Success — pane focused
          1  Error (app not running, invalid ID, pane not found)

        Examples:
          symterminal focus 6BA7B810-9DAD-11D1-80B4-00C04FD430C8
          symterminal focus 6BA7B810-... --json
        """)
    }
}

// MARK: - mcp command

struct MCPCommand {
    let flags: [String]

    func run() async {
        if flags.contains("--help") || flags.contains("-h") {
            printHelp()
            return
        }

        let server = MCPStdioServer()
        await server.run()
    }

    private func printHelp() {
        print("""
        Usage: symterminal mcp

        Start an MCP (Model Context Protocol) server over stdio, proxied to
        the running Symaira Terminal instance. Reads JSON-RPC requests from
        stdin and writes responses to stdout.

        Available tools:
          list_agents            List all panes and their agent status
          read_pane_output       Read scrollback from a terminal pane
          get_pending_approvals  List pending approval requests
          spawn                  Open a new pane running an agent
          focus                  Select an existing pane by UUID
          blocked                Report the longest-blocked agent

        Exit codes:
          0  Clean shutdown
          1  Symaira Terminal is not running, or another error occurred

        Config snippet (add to your MCP-capable agent's config):
          {
            "mcpServers": {
              "symaira-terminal": {
                "command": "symterminal",
                "args": ["mcp"]
              }
            }
          }
        """)
    }
}
