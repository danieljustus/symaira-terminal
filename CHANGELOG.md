# Changelog

All notable changes to Symaira Terminal will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### M4 — Polish & Launch (in progress)

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

[Unreleased]: https://github.com/danieljustus/symaira-terminal/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/danieljustus/symaira-terminal/releases/tag/v0.1.0
