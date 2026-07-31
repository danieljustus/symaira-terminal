# ADR 001: Symaira AppKit Module Evaluation

Status: accepted (2026-07-31)
Refs: #314

## SymairaKeychain → **Adopted**

Replaced direct Security framework calls (`SecItemAdd`, `kSecClassGenericPassword`,
etc.) in `KeychainKeyStore` and `KeychainTokenStore` with `SymairaKeychain` from
symaira-appkit. Existing credentials are automatically migrated from legacy service
names on first access per profile.

Commit: `ffc8b93`

## SymairaCLIRunner → **Not adopted (consciously local)**

The five `Process()` call sites in the codebase are:

| File | Purpose | Why not CLIRunner |
|---|---|---|
| `WorktreeManager.swift` | `git` subprocess | Not a Symaira tool |
| `ProcessRunner.swift` | Generic git process with PTY-aware output capture | Needs real-time stdout/stderr interleaving; CLIRunner captures both separately |
| `StackDetector.swift` | `--version` query for Symaira tools | Runs `Process()` with timeout; CLIRunner adds PATH augmentation but the heavy lifting (binary location, version parsing) is already in StackDetector |
| `ACPClient.swift` | Long-running agent subprocess (JSON-RPC over stdio) | Interactive, long-lived process with bidirectional stdio — CLIRunner is fire-and-forget |
| `WorktreeStore.swift` | `git diff --stat` dirty check | One-line git invocation |

`CLIRunner` is designed for fire-and-forget Symaira CLI tool invocations with
structured JSON output and schema validation. The terminal app's Process() calls
are either git subprocesses, interactive agent processes, or already have their own
timeout/wrapper logic. Replacing them with `CLIRunner` would add indirection without
benefit.

## SymairaTheme → **Not adopted (consciously local, deferred to #315)**

The app uses Apple semantic colors (`Color.secondary`, `.red`, `.green`) and a
custom dark background (`Color(red: 11/255, green: 13/255, blue: 17/255)`). These
adapt to light/dark mode automatically and match the terminal's native appearance.

`SymairaTheme` provides a champagne-gold / warm-neutral palette designed for the
broader Symaira ecosystem. Adopting it would require a full color scheme redesign
of the terminal app. This is exactly the scope of #315 (Design-System), which
should make the final decision on theme adoption alongside typography and form
components.

## .claude/worktrees/ → **Already removed**

The stale worktree under `.claude/worktrees/` no longer exists on disk. The
`.gitignore` already covers `.build/`, and `.worktrees/` was added in commit
`04627d9`. No further action needed.
