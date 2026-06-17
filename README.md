# Symaira Terminal

[![CI](https://github.com/danieljustus/symaira-terminal/actions/workflows/ci.yml/badge.svg)](https://github.com/danieljustus/symaira-terminal/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Release](https://img.shields.io/github/v/release/danieljustus/symaira-terminal)](https://github.com/danieljustus/symaira-terminal/releases)

A native macOS terminal built for the Human-AI era — designed for running multiple
CLI coding agents (Claude Code, OpenCode, Aider, Gemini CLI, …) in parallel without
losing track of what they are doing.

**Status: beta (v0.7.0).** Core terminal rendering works; multi-pane,
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

<!-- TODO: Add screenshot showing multi-pane layout with agent status rings -->
<!-- ![Symaira Terminal Screenshot](docs/screenshot.png) -->

## Installation

### Homebrew (recommended)

```bash
brew tap danieljustus/tap
brew install --cask symterminal
```

### Manual

Download the latest `.dmg` from [GitHub Releases](https://github.com/danieljustus/symaira-terminal/releases), mount it, and drag `SymairaTerminal.app` to your Applications folder.

**Note:** The app is currently unsigned (no Apple Developer account). macOS will block it by default. To allow it, run this once after installing:

```bash
xattr -cr /Applications/SymairaTerminal.app
```

Or right-click the app → "Open" → "Open" to bypass Gatekeeper.

## Usage

Once installed, launch Symaira Terminal from your Applications folder or via Spotlight.

### Basic Workflow

1. **Open a pane** — Click the `+` button or use `Cmd+T` to create a new terminal pane
2. **Run an agent** — Execute your CLI agent as usual:
   ```bash
   claude "implement the login feature"
   ```
3. **Monitor status** — Watch the status ring around each pane:
   - 🟢 **Running** — Agent is actively working
   - 🟡 **Awaiting approval** — Agent needs your input
   - 🔴 **Error** — Agent encountered a problem
4. **Jump to blocked agent** — Use `Cmd+Shift+U` to focus the longest-blocked agent

### Multi-Agent Example

```bash
# Pane 1: Feature implementation
claude "add user authentication"

# Pane 2: Test writing
aider --test-only "write tests for auth module"

# Pane 3: Documentation
gemini "update README with new auth flow"
```

Each agent runs in its own pane with independent status tracking. The workspace sidebar shows all active agents at a glance.

### BYOK (Bring Your Own Key)

Configure your API providers in Settings (`Cmd+,`):

- **Anthropic** — Use your Anthropic API key
- **OpenAI** — Use your OpenAI API key
- **OpenRouter** — Access multiple providers through one key
- **Google** — Use Gemini API key
- **Ollama** — Local models, no key needed
- **Custom** — Any OpenAI-compatible endpoint

Keys are stored securely in the macOS Keychain — never sent to Symaira servers.

## License

MIT — see [LICENSE](LICENSE). Like all other Symaira cores, Symaira Terminal is
open-source under the MIT License. The Symaira name, logo, and app icon are
protected trademarks — see [TRADEMARK.md](TRADEMARK.md). Third-party dependency
notices are in [NOTICE](NOTICE). This app is fully self-contained: it builds and
runs without any account, cloud service, or external backend.

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

See [docs/architecture-plan-v1.md](docs/architecture-plan-v1.md) (v1 core-MVP plan,
German) and the ADRs in [docs/adr/](docs/adr/).
