# Changelog

All notable changes to Symaira Terminal will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.8.1] — 2026-06-26

### Fixed
- `symterm +tab` now joins all CLI arguments and passes the caller's working directory through the URL scheme (#218)
- `TerminalCore` is now free of AppKit types; view-hosting is accessed via downcast in the App layer (#219)
- `SecretRedactor` moved from `ProviderKit` to `TerminalCore`, removing the sideways `WorktreeKit → ProviderKit` dependency (#220)
- Enforce the advertised local socket connection cap (#214)
- Avoid embedding Homebrew tap PAT in git clone URL (#215)
- Honor MCP scrollback schema contract — `read_pane_output` without `pane_id` now returns focused pane output (#216)
- Clear app-owned scrollback buffer when users clear scrollback (#217)
- Wire incremental usage reads and throttle quota refreshes (#221, #222)

### Changed
- Bump `actions/checkout` from 6.0.3 to 7.0.0 (#212)
- Make Release workflow idempotent — upload DMG to existing release when tag already exists (#211)

## [0.8.0] — 2026-06-22

### Added
- `symterm` CLI wrapper for opening Symaira Terminal from any shell, IDE terminal, or script (#176)
- `symterminal` companion CLI for querying and driving the running app from scripts, tmux status bars, and CI (#171, #190)
- ControlKit: local Unix-socket agent control surface so external agents and scripts can observe and orchestrate multi-agent state (#190)
- MCP server with read-scrollback and request-open-tab tools, enabling MCP-capable agents to inspect terminal output and open tabs (#177)
- Unified MCP type system and shared helpers across the ACP/MCP stack (#191)
- `ProviderCredential` model that unifies how provider keys and OAuth tokens are stored and redacted
- BYOK status now visible per provider profile in settings

### Changed
- Reworked `SessionPersistence` and `AgentStatus` internals to support the new control-surface events
- Split pane/agent orchestration responsibilities to keep the app target thin and the library targets reusable

### Fixed
- OAuth/PKCE redirect and token-handling edge cases for Google and OpenAI providers
- `SecretRedactor` unified across ProviderKit so secrets are consistently scrubbed from logs and transcripts
- Provider chat client error paths and retry behavior
- Agent catalog and transcript storage race conditions under concurrent agents

### Security
- Review-driven hardening of ControlKit IPC permissions and input validation (#202)
- Secret redaction applied consistently across ProviderKit, usage tracking, and logging paths

### Performance
- Reduced unnecessary worktree and process state churn during heavy multi-agent sessions (#202)

## [0.7.0] — 2026-06-17

### Added
- Multi-Agent Workflow Canvas: visual React Flow editor for wiring agent task connections and handoff pipelines (#97)
- Confirmation dialog for distributed notification handoff (#143)
- SwiftLint CI workflow with strict mode (#153)
- Swift ecosystem Dependabot configuration (#159)

### Fixed
- OSC 7 directory path parsing with spaces (#146)
- ProcessRunner thread starvation via blocking I/O (#149)
- UsageHTTPServer partial TCP read framing (#151)
- WorkspaceMonitor lsof parser for command names with spaces (#154)
- SwiftLint violations across 48 files (#153)

### Security
- Enforce squash merge only in repository settings (#144)

### Chores
- Disable blank issues in GitHub issue templates (#145)
- Ignore .omo/ in gitignore

## [0.6.0] — 2026-06-15

### Added
- OAuth/PKCE provider sign-in support (OpenAI, Google) — browser-based auth instead of API keys
- IDE-like input editor for terminal pane
- OSC 8 hyperlink parsing for clickable links in terminal output

### Fixed
- Pipe deadlock in terminal session handling
- TTL caching for provider responses
- Model defaults for OpenAI-compatible providers
- Dead transcript UI elements
- Terminal input handling improvements
- OSC handling hardening

### Security
- Security hardening across multiple modules
- Performance and architecture improvements

### Docs
- Removed private/commercial repository references from public docs
- Removed superseded research plan, linked curated v1 plan

## [0.4.0] — 2026-06-14

### Added
- UsageKit: local AI usage and cost tracking for Claude Code, Codex, Gemini CLI, and more
- Usage pricing tables: convert token counts to USD cost per model
- Usage aggregation engine: today/week/month/session buckets with 5-hour billing windows
- Subscription quota fetchers: plan session/weekly limits and credits (opt-in, credential-safe)
- Usage UI: status-bar summary and detail panel with progress bars and badges
- Usage refresh scheduler: incremental log tailing, debounced polling, App Nap aware
- Optional local usage HTTP API for interop with other apps (loopback, opt-in, off by default)
- StackKit module: MCP hub, stack detection, settings UI

## [0.2.0] — 2026-06-11

### Fixed
- Prevent SIGSEGV crash in saveSession() during app termination
- Use configured baseURL for openai-compatible provider instead of hardcoding api.openai.com
- Add 30s timeout to AI requests with proper error handling
- Update stale default models (claude-sonnet-4, gemini-2.5-flash, llama3.1, etc.)
- Make WorkspaceConfigManager.save() throwing for proper error propagation

### Added
- Community files (CONTRIBUTING.md, CODE_OF_CONDUCT.md, SECURITY.md, CODEOWNERS, issue/PR templates)
- Rename Homebrew cask from symaira-terminal to symterminal

### Security
- Pin CI actions to SHA for supply-chain security
- Add Dependabot config for github-actions ecosystem

### Performance
- Optimize scrollback search with debounce and caching

### Refactored
- Consolidate provider definitions into ProviderDescriptor pattern

#### Added
- Blocks-lite shell integration (zsh/bash/fish OSC 133 snippets)
- Multi-Account-Routing with workspace config (.symaira/config.json)
- Onboarding-Flow with 3-step setup (API key, shell integration, ready)
- Settings UI with General, Providers, Workspace, Advanced tabs
- Release script with archive, notarize, DMG, GitHub release flow
- Sparkle appcast template for auto-updates
- Homebrew Cask formula

### M3 — Agent-Aware Features (completed)

#### Added
- Worktree-Manager UI with create, list, remove, dirty indicator
- Diff-Review-Panel with syntax-highlighted unified diff
- Context Bank UI with file list, editor, and role templates
- ProviderKit / BYOK UI with profile management
- "Fehler beheben" button with AI error analysis
- NL→Command in Command Palette
- ACP-Client for OpenCode integration
- Gemini CLI ACP adapter with tool name normalization

### M1 — Terminal Infrastructure (completed)

#### Added
- Multi-pane window management (NSSplitView + PaneManager)
- Tab bar with pane switching (TabBarView)
- Session state persistence (SessionState, SessionPersistence with atomic writes)
- OSC event handler wiring parser to AgentStatusEngine
- LatencyBench harness for M1 performance gate
- GhosttyTheme catalog integration (theme/font/ligature parsing from ~/.config/ghostty/config)
- ScrollbackBuffer with full-text search (⌘F)
- WorkspaceSidebar with worktree section

#### Fixed
- App target import wiring (4 fix commits)

## [0.1.0] — 2026-06-10

### M0 — Project Spike (completed)

#### Added
- Project scaffolding with AGPLv3 license
- AGENTS.md and docs/commercial-boundary.md
- CI workflow (.github/workflows/ci.yml)
- XcodeGen project.yml with App target
- SymairaKit SPM package with 7 library targets:
  - TerminalCore (OSC parser, PTY session, environment sanitizer)
  - GhosttyBridge (GhosttyKit integration, Metal rendering)
  - AgentKit (status engine, agent catalog)
  - WorktreeKit (git worktree management)
  - ProviderKit (Keychain-backed BYOK)
  - ContextBank (CLAUDE.md/AGENTS.md locator)
  - SymairaUI (status ring view)
- TerminalSmoke executable (GhosttyKit spike: zsh renders in SwiftUI)
- libghostty-spm pinned at exact version 1.2.4
- 26 unit tests across all modules
- ADR-001: Terminal engine choice + pin strategy

[Unreleased]: https://github.com/danieljustus/symaira-terminal/compare/v0.8.3...HEAD
[0.8.0]: https://github.com/danieljustus/symaira-terminal/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/danieljustus/symaira-terminal/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/danieljustus/symaira-terminal/compare/v0.5.0...v0.6.0
[0.4.0]: https://github.com/danieljustus/symaira-terminal/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/danieljustus/symaira-terminal/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/danieljustus/symaira-terminal/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/danieljustus/symaira-terminal/releases/tag/v0.1.0
