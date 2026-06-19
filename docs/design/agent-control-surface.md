# Agent Control Surface Design

The control surface is a local, headless interface that lets external agents and
scripts **observe and drive** the orchestration state of a running Symaira Terminal
instance — without the GUI. It is consumed by:

- **`symterminal status [--json]`** — read-only CLI snapshot
- **`symterminal spawn / focus / blocked`** — write CLI verbs
- **`symterminal mcp`** — MCP stdio server exposing the same surface as tools

Transport: Unix domain socket. See
[ADR-002](../adr/ADR-002-control-surface-transport.md) for the rationale.

---

## Module: ControlKit

A new SPM library target `ControlKit` is added to `Packages/SymairaKit/Package.swift`.

### Dependency direction

```
App ──────────────────────────────────────────────────────┐
                                                          ▼
ControlKit ──► AgentKit ──► TerminalCore ──► GhosttyBridge
           └──► WorktreeKit

symterminal ──► ControlKit
```

`ControlKit` depends on `AgentKit` (for `AgentStatus`, `StatusSource`,
`StatusObservation`) and `WorktreeKit` (for worktree names/paths). The `App` target
depends on `ControlKit` to vend the socket server. The `symterminal` executable
target depends on `ControlKit` for the client connector. This satisfies the
dependency direction in `AGENTS.md`: no upward or sideways imports are introduced.

### Contents

| Component | Role |
|---|---|
| `OrchestrationControl` protocol | Defines the full verb set (read + write) |
| `OrchestrationSnapshot` | `Codable` DTO — the read-only view of app state |
| `PaneSnapshot` | Per-pane entry in the snapshot |
| `WorktreeSnapshot` | Per-worktree entry |
| `ApprovalSummary` | Pending approval (observe-only) |
| `ControlRequest` / `ControlResponse` | JSON-RPC wrapper types |
| `ControlServer` | Binds the socket, dispatches requests on the main actor |
| `ControlClient` | Connects to the socket, sends requests, receives responses |

---

## Snapshot schema

`OrchestrationSnapshot` is the top-level read-only DTO returned by the `snapshot`
verb and all read tools. All fields are `Codable` and `Sendable`.

```swift
public struct OrchestrationSnapshot: Codable, Sendable {
    public var panes: [PaneSnapshot]
    public var currentPaneID: UUID?
    public var pendingApprovals: [ApprovalSummary]
    public var worktrees: [WorktreeSnapshot]
    public var appVersion: String
    public var capturedAt: Date
}

public struct PaneSnapshot: Codable, Sendable {
    public var id: UUID
    public var title: String
    public var workingDirectory: String?
    public var agentStatus: AgentStatus
    public var agentStatusSource: StatusSource
    public var agentDetail: String?
    public var isCurrent: Bool
    public var isZoomed: Bool
    public var worktreeBranch: String?
}

public struct WorktreeSnapshot: Codable, Sendable {
    public var branch: String
    public var path: String
    public var hasUncommittedChanges: Bool
    public var linkedPaneID: UUID?
}

public struct ApprovalSummary: Codable, Sendable {
    public var paneID: UUID
    public var agentName: String?
    public var promptSummary: String
    public var waitingSince: Date
}
```

`PaneSnapshot` reuses `AgentStatus` and `StatusSource` directly from `AgentKit`.
`ApprovalSummary` is **read-only** — there is no approve or deny field. The human
in the loop handles approvals exclusively through the GUI.

---

## Verb set

### Read verbs (observation)

| Verb | JSON-RPC method | Description |
|---|---|---|
| `snapshot` | `control/snapshot` | Returns `OrchestrationSnapshot` |
| `panes` | `control/panes` | Returns `[PaneSnapshot]` |
| `pendingApprovals` | `control/pendingApprovals` | Returns `[ApprovalSummary]` |
| `worktrees` | `control/worktrees` | Returns `[WorktreeSnapshot]` |

### Write verbs (orchestration)

| Verb | JSON-RPC method | Description |
|---|---|---|
| `spawn` | `control/spawn` | Open a new pane running a named agent |
| `focus` | `control/focus` | Make a pane current by ID |
| `blocked` | `control/blocked` | Report (and focus) the longest-blocked pane |

### Explicitly absent verbs

| Verb | Reason |
|---|---|
| `approve` | Approvals are human-only. The protocol has no such method. |
| `deny` | Same. |
| `kill` | Out of scope for v0.8.0. |
| `input` | Typing into panes is not exposed (no arbitrary code injection). |

The absence of approve/deny is **structural**, not just "not implemented yet". The
`OrchestrationControl` protocol has no corresponding method signatures, so no
transport layer can expose them — the capability does not exist in the type system.

---

## Read-vs-write boundary

```
Read  (snapshot, panes, pendingApprovals, worktrees)
  │   → safe for any connected local process of the same user
  │   → no state mutation, no side-effects, idempotent
  │
Write (spawn, focus, blocked)
  │   → runs on the @MainActor via PaneManager
  │   → validated: pane IDs checked before focus; spawn validates agent name
  │   → error on invalid input; no partial mutations
  │
Approval/deny ──► GUI only (AppKit confirmation sheet, never exposed on socket)
```

Write verbs cross the socket → main actor boundary via a structured request that
the `ControlServer` dispatches after validation. Invalid requests return a JSON-RPC
error; they never crash or partially mutate state.

---

## Access control

The socket file is created at:

```
~/Library/Application Support/Symaira Terminal/control.sock
```

with permissions `0600` at bind time, restricting access to the owning user. The
security-boundary issue (same milestone) adds:

1. A test asserting that a non-owner-UID connection is refused.
2. A verification that agents spawned via `control/spawn` pass through
   `EnvironmentSanitizer` before their environment is set.

---

## Protocol wire format

Line-delimited JSON-RPC 2.0. Each message is a single UTF-8 JSON object followed
by `\n`. Framing reuses the `ACPMessage` type from `AgentKit`.

**Request:**
```json
{"jsonrpc":"2.0","method":"control/snapshot","params":{},"id":1}
```

**Response (success):**
```json
{"jsonrpc":"2.0","result":{...OrchestrationSnapshot...},"id":1}
```

**Response (error):**
```json
{"jsonrpc":"2.0","error":{"code":-32602,"message":"unknown pane id"},"id":1}
```

Error codes follow JSON-RPC 2.0 conventions. The transport does not support
notifications (server push) in v0.8.0; polling via `control/snapshot` is the
baseline, with a subscribe mechanism deferred to a later iteration.

---

## Stale socket recovery

If the app crashes without cleanup, the socket file persists but nothing is bound
to it. Clients detect `ECONNREFUSED` on connect and report:

```
Error: Symaira Terminal is not running (no listener on control socket).
```

The next app launch re-binds the socket, overwriting the stale file.
