import ControlKit
import Foundation

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
