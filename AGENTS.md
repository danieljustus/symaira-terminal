# Agent Instructions — symaira-terminal

Native macOS terminal app (Swift 6, AppKit/SwiftUI, libghostty engine). Public repo,
MIT-licensed. Part of the Symaira family — see `../AGENTS.md` for the cross-repo
conventions and `docs/commercial-boundary.md` for the public/pro boundary.

## Build & Test

```bash
cd Packages/SymairaKit
swift build                 # all library targets
swift test                  # unit tests (no GUI required)
```

App bundle (GUI):

```bash
xcodegen generate           # project.yml → SymairaTerminal.xcodeproj (not checked in)
xcodebuild -project SymairaTerminal.xcodeproj -scheme SymairaTerminal build
```

## Module Layout (Packages/SymairaKit, one package, multiple targets)

Dependency direction is enforced by SPM target dependencies — do not add upward or
sideways imports:

```
App → SymairaUI → {AgentKit, WorktreeKit, ProviderKit, ContextBank} → TerminalCore → GhosttyBridge
```

- `GhosttyBridge` — the ONLY target allowed to touch the GhosttyKit C API.
  Everything else talks to the `TerminalEngine` protocol. Keep it this way so the
  engine stays swappable (libghostty's API is not stable yet; pin exact versions).
- `TerminalCore` — PTY lifecycle, session persistence, OSC parser (133, 7, 8, 777,
  99/Kitty), child-process env hygiene. No AppKit imports here.
- `AgentKit` — agent detection, status engine (`idle/running/awaitingApproval/error/done`),
  ACP client (JSON-RPC over stdio). Status source priority: ACP > OSC > heuristics.
- `WorktreeKit` — git worktree lifecycle, FSEvents watching, diffs.
- `ProviderKit` — BYOK. API keys go to the macOS Keychain ONLY. Never write keys to
  config files, never send them to any Symaira service, never log them.
- `ContextBank` — CLAUDE.md/AGENTS.md editing backend, role templates, rules.
- `SymairaUI` — SwiftUI/AppKit views (sidebar, palette, status rings, blocks-lite).

## Hard Rules

- **Local-first**: no telemetry, no account requirement, no network calls except
  user-configured AI providers and explicit user actions (e.g. update check).
- **No web stack for terminal rendering** (no Electron/xterm.js/WKWebView panes for
  shell output). WKWebView is allowed only for post-v1 auxiliary panels.
- **Public/pro boundary**: no billing, tenant, or cloud-deployment code in this
  repo. If a future pro service needs a core capability, implement it here first,
  release/tag it, then let the private repo consume the tagged artifact.
- **Env hygiene**: when spawning nested agent processes, strip provider secrets and
  agent flags (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `CLAUDECODE`, …) from the
  child environment unless a workspace profile explicitly injects them
  (`TerminalCore/EnvironmentSanitizer`).
- **Zero stdout pollution in stdio protocol code**: the ACP client communicates via
  JSON-RPC over stdio pipes; log to stderr/os_log only.
- Swift 6 strict concurrency: new code must compile with `StrictConcurrency` enabled.

## Testing Quirks

- PTY tests spawn real `/bin/zsh` processes; they are skipped when `CI=true` sets
  no controlling terminal — keep them robust against sandboxed environments.
- WorktreeKit tests create throwaway git repos under `NSTemporaryDirectory()`.
- Keychain-dependent tests use an in-memory `KeyStore` mock; never touch the real
  Keychain in tests.
