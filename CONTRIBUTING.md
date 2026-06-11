# Contributing to Symaira Terminal

Thank you for your interest in contributing to Symaira Terminal! This document provides guidelines and information for contributors.

## Development Setup

### Prerequisites

- macOS 14+ (Sonoma or later)
- Xcode 26+ / Swift 6.1+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (for app target)

### Getting Started

1. Fork the repository on GitHub
2. Clone your fork locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/symaira-terminal.git
   cd symaira-terminal
   ```
3. Create a branch for your changes:
   ```bash
   git checkout -b feature/your-feature-name
   ```

### Building

#### Library (SymairaKit)

```bash
cd Packages/SymairaKit
swift build
swift test
```

#### App Target

```bash
xcodegen generate
xcodebuild -project SymairaTerminal.xcodeproj -scheme SymairaTerminal build
```

## Pull Request Process

1. **Create a focused PR**: Each PR should address a single concern (bug fix, feature, refactor).
2. **Write clear commit messages**: Use conventional commit format when possible.
3. **Add tests**: For new features or bug fixes, include tests that cover your changes.
4. **Update documentation**: If your change affects user-facing behavior, update the README.
5. **Ensure CI passes**: All checks must pass before merge.

### PR Title Convention

- `feat: add new feature`
- `fix: resolve bug`
- `docs: update documentation`
- `refactor: improve code structure`
- `test: add missing tests`

## Code Style

- Follow existing code patterns in the repository
- Use Swift 6 strict concurrency features
- Keep imports minimal and explicit
- Write self-documenting code with clear naming

## Architecture Overview

The project uses a modular architecture with clear dependency boundaries:

```
App → SymairaUI → {AgentKit, WorktreeKit, ProviderKit, ContextBank} → TerminalCore → GhosttyBridge
```

- **GhosttyBridge**: Only target allowed to touch GhosttyKit C API
- **TerminalCore**: PTY lifecycle, session persistence, OSC parser
- **AgentKit**: Agent detection, status engine, ACP client
- **WorktreeKit**: Git worktree lifecycle, FSEvents watching
- **ProviderKit**: BYOK, API keys in macOS Keychain only
- **ContextBank**: CLAUDE.md/AGENTS.md editing backend
- **SymairaUI**: SwiftUI/AppKit views

## Testing

- Unit tests are in `Packages/SymairaKit/Tests/`
- Run tests with `swift test` from the `Packages/SymairaKit` directory
- PTY tests are skipped in CI (no controlling terminal)
- Keychain tests use in-memory mocks

## Reporting Issues

- Use GitHub Issues for bug reports and feature requests
- Include reproduction steps for bugs
- Specify your macOS and Xcode versions

## License

By contributing, you agree that your contributions will be licensed under the AGPLv3 License.
