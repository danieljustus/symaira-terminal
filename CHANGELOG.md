# Changelog

All notable changes to Symaira Terminal will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### M1 — Terminal Infrastructure (in progress)

#### Added
- Multi-pane window management (NSSplitView + PaneManager)
- Tab bar with pane switching (TabBarView)
- Session state persistence (SessionState, SessionPersistence with atomic writes)
- OSC event handler wiring parser to AgentStatusEngine
- LatencyBench harness for M1 performance gate
- GhosttyTheme catalog integration (theme/font/ligature parsing from ~/.config/ghostty/config)
- ScrollbackBuffer with full-text search (⌘F)
- WorkspaceSidebar (SwiftUI, not yet embedded in app window)

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
