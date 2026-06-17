# ADR-002: Agent Control Surface Transport — Unix Domain Socket

Status: accepted (2026-06-17)

## Context

Symaira Terminal needs a local, headless control surface so external agents and scripts
can **observe and drive** multi-agent orchestration without the GUI. The surface is
consumed by two clients: a `symterminal` CLI tool and an MCP stdio server
(`symterminal mcp`).

Requirements:

- **Local-only**: no network exposure, no remote access. Matches the AGENTS.md
  "local-first" hard rule.
- **Single-user**: only processes of the same macOS user may connect.
- **CLI-accessible**: a standalone executable (`symterminal`) that is not a launchd
  service must be able to connect without registration.
- **Sandbox-compatible**: the app may be distributed with or without App Sandbox;
  the transport must work in both configurations.
- **No stdout pollution**: must not conflict with the MCP stdio protocol, which uses
  stdin/stdout for JSON-RPC frames.
- **Swift 6**: all server and client code must compile with `StrictConcurrency`.

## Candidates

### 1. Unix domain socket (chosen)

A socket file at a stable path in the app's Application Support directory:

```
~/Library/Application Support/Symaira Terminal/control.sock
```

The file is created with permissions `0600` at bind time (owner read/write only).
The app cleans it up on clean exit; `symterminal` checks for a stale socket on
connect (bind fails → app not running).

**Pros:**
- Works without App Sandbox entitlements (socket in the container's support dir is
  allowed by default).
- Any local process of the same user can connect with a standard POSIX socket call —
  no launchd registration, no Mach service lookup.
- Simple, well-understood protocol surface: line-delimited JSON over a stream socket,
  mirroring the existing `ACPClient` pattern.
- Easy to test: mock server and client can run in-process via a socketpair.
- No stdout interference: I/O is not stdio.

**Cons:**
- Relies on filesystem permissions for access control. A process running as the same
  user but in a different security context (e.g. a jailed subprocess) can connect.
  Accepted: `EnvironmentSanitizer` already governs spawned-agent environments; the
  security-boundary issue adds a capability split so approval verbs are absent from
  the protocol entirely.
- Stale socket file if the app crashes without cleanup. Mitigated: client detects
  ECONNREFUSED and falls back to a clear "app not running" error.

### 2. NSXPC / XPC Service

Apple's recommended IPC for sandboxed apps. Type-safe Swift interface, process
lifecycle managed by launchd.

**Rejected because:**
- `symterminal` is a user-installed CLI, not a registered launchd service. Anonymous
  NSXPC connections require a known Mach service name, which requires launchd
  registration — adding a non-trivial install step.
- An XPC Service bundle (separate process) would duplicate the app's orchestration
  state rather than reading it directly from the `@MainActor` `PaneManager`.
- Adds dependency on entitlement provisioning, which complicates ad-hoc development
  builds.

### 3. Mach service (CFMessagePort / low-level bootstrap)

Low-level port-based IPC, also requires launchd registration for inter-process use
by arbitrary CLI tools. Same rejection rationale as NSXPC.

## Decision

**Unix domain socket** at the well-known path:

```
~/Library/Application Support/Symaira Terminal/control.sock
```

Protocol: **line-delimited JSON-RPC 2.0** (one JSON object per line, `\n`-terminated),
reusing the `ACPMessage` / `AnyCodable` types already in `AgentKit`. The socket is
created with `0600` permissions and is bound exclusively to the running app instance.

The `ControlKit` library target (see design doc) owns both the server half (bound by
the App at startup) and the client half (used by `symterminal` and the MCP server).

## Consequences

- A single well-known socket path means only one running app instance is supported
  per user at a time. Acceptable for v0.8.0; a lock-file or PID-in-path scheme can
  multi-instance later.
- Stale socket recovery is the client's responsibility: ECONNREFUSED → report "Symaira
  Terminal is not running" and exit non-zero.
- The security-boundary issue (same milestone) must: (a) enforce `0600` at bind time,
  (b) ensure the approval/deny verbs are structurally absent from `OrchestrationControl`
  (not just unimplemented), and (c) verify that agents spawned via the control surface
  pass through `EnvironmentSanitizer`.
- The MCP server (`symterminal mcp`) connects to the same socket as the CLI; it must
  write zero bytes to stdout other than MCP protocol frames (use `os_log`/stderr for
  diagnostics, consistent with the AGENTS.md zero-stdout-pollution rule).
