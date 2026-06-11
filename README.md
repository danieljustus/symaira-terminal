# Symaira Terminal

A native macOS terminal built for the Human-AI era — designed for running multiple
CLI coding agents (Claude Code, OpenCode, Aider, Gemini CLI, …) in parallel without
losing track of what they are doing.

**Status: beta (v0.1.0).** Core terminal rendering works; multi-pane,
session persistence, agent status rings, worktree isolation, BYOK, ACP integration,
and shell integration are functional. See [CHANGELOG.md](CHANGELOG.md) for details.

## Why another terminal?

Classic terminals were built for sequential human typing. When several autonomous
agents modify code, run servers, and wait for approvals at the same time, tabs and
scrollback are not enough. Symaira Terminal is agent-aware by design:

- **Native & fast** — Swift 6 + AppKit/SwiftUI shell around the Metal-accelerated
  [libghostty](https://ghostty.org) engine. No Electron, no xterm.js.
- **Agent status system** — per-pane status rings (running / awaiting approval /
  error), a workspace sidebar, and a hotkey that jumps to the longest-blocked agent.
- **Dual-mode agent integration** — every CLI agent works unchanged via PTY;
  ACP-capable agents ([Agent Client Protocol](https://agentclientprotocol.com))
  additionally get structured permission dialogs, tool-call timelines, and diffs.
- **Git worktree isolation** — each agent task runs in its own transient worktree
  with a review panel before merging back.
- **BYOK for everyone, in the free open-source app** — bring your own API key
  (Anthropic, OpenAI, OpenRouter, Google, Ollama, any OpenAI-compatible endpoint).
  Keys live in the macOS Keychain only. No account, no cloud middleman, no telemetry.
- **Local-first** — configuration, prompt history, and transcripts stay on your Mac.

## Installation

### Homebrew (recommended)

```bash
brew tap danieljustus/tap
brew install --cask symaira-terminal
```

### Manual

Download the latest `.dmg` from [GitHub Releases](https://github.com/danieljustus/symaira-terminal/releases), mount it, and drag `SymairaTerminal.app` to your Applications folder.

**Note:** The app is currently unsigned (no Apple Developer account). macOS will block it by default. To allow it, run this once after installing:

```bash
xattr -cr /Applications/SymairaTerminal.app
```

Or right-click the app → "Open" → "Open" to bypass Gatekeeper.

## License

AGPLv3 — see [LICENSE](LICENSE). Unlike the other Symaira cores (MIT), the terminal
uses AGPLv3 deliberately: the full local product including BYOK stays free for
everyone, and improvements to distributed forks must remain open. Commercial cloud
services (team sync, mobile companion relay, hosted tunnels) will live in a separate
private repository and are not required to build or run this app — see
[docs/commercial-boundary.md](docs/commercial-boundary.md).

## Building

Requires Xcode 26+ / Swift 6.1+ on macOS 14+.

```bash
cd Packages/SymairaKit
swift build
swift test
```

App target (requires [XcodeGen](https://github.com/yonaskolb/XcodeGen)):

```bash
xcodegen generate
xcodebuild -project SymairaTerminal.xcodeproj -scheme SymairaTerminal build
```

## Architecture

See [docs/Systemarchitektur und Entwicklungsplan.md](docs/Systemarchitektur%20und%20Entwicklungsplan.md)
(research, German) and the ADRs in [docs/adr/](docs/adr/).
