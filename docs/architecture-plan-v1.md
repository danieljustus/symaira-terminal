# Symaira Terminal — Architekturplan (v1 Core-MVP)

## Kontext

Symaira baut Tools für die Human-AI-Era. Nächstes Produkt: ein natives macOS-Terminal, optimiert für Vibe Coding mit parallelen CLI-Agenten (Claude Code, OpenCode, Aider, Gemini CLI). Differenzierung zu Warp: **Local-First + BYOK für alle bereits in der Open-Source-Variante** — kein Account-Zwang, keine AI-Cloud-Pipeline des Herstellers.

Entscheidungen des Users (10.06.2026):
- **Scope v1**: Fokussiertes Core-MVP (~4 Monate). Canvas, Mobile App, Tunnel, STT/Sketchpad nach v1.
- **Open-Core**: nach Symaira-Konvention — Public Core Repo + privates `-pro`-Repo (Go, `symaira-prokit`, Google Cloud + Firebase + Stripe).
- **Lizenz**: AGPLv3 für `symaira-terminal` (bewusste Abweichung von MIT der anderen Cores — im Repo-README/commercial-boundary.md begründen).

Projektstand: Greenfield. Nur `docs/Systemarchitektur und Entwicklungsplan.md` existiert.

## Bewertung des bisherigen Research

**Bestätigt (Stand Juni 2026, web-verifiziert):**
- libghostty/GhosttyKit als Metal-beschleunigte Engine ist der richtige Ansatz; `libghostty-spm` liefert ein prebuilt `GhosttyKit.xcframework` als Swift Package. cmux beweist die Machbarkeit.
- Anti-Patterns (kein Electron/xterm.js fürs Terminal, kein Orchestrator-Lock-in, Env-Var-Hygiene bei verschachtelten Agenten) sind korrekt und bleiben Leitplanken.
- Worktree-Isolierung, Status-Leitsystem, Context Bank, Command Palette: alles valide Kernfeatures.

**Korrekturen am Research:**
1. **Warp ist seit 28.04.2026 selbst Open Source (Client unter AGPLv3, OpenAI als Sponsor).** Die Positionierung „wir sind open, Warp nicht" trägt nicht mehr. Neue Differenzierung: Warps AI läuft weiterhin über deren proprietäre Cloud („Oz", Login-Zwang, BYOK nur Enterprise) — Symaira Terminal ist local-first, BYOK-frei, agent-agnostisch.
2. **OSC 133 (Semantic Prompts) fehlt im Research.** Das ist der etablierte Standard (FinalTerm/iTerm2/Ghostty-Shell-Integration) für Command-Blöcke, Exit-Codes und Prompt-Navigation — die Grundlage für „Blocks-lite" (siehe unten), deutlich billiger als Warps Block-Rendering.
3. **ACP (Agent Client Protocol) fehlt im Research.** 25+ Agenten unterstützen es (Gemini CLI, Copilot CLI, OpenCode, …), JSON-RPC über stdio, seit 2026 unter Linux-Foundation-Dach, mit Registry. Damit werden Agent-Status („wartet auf Freigabe", Tool-Calls, Diffs) **strukturiert** geliefert statt per PTY-Heuristik geraten. → Dual-Mode-Integration (unten) ist die wichtigste Architektur-Ergänzung.
4. **libghostty-API ist offiziell noch instabil** („API signatures in flux"). → exakte Version pinnen und alle C-API-Aufrufe in einem einzigen Modul isolieren.
5. **Warp-Blöcke wörtlich nachzubauen lohnt für Vibe Coding kaum:** Claude Code/OpenCode sind Fullscreen-TUIs (Alternate Screen) — dort greifen Blöcke gar nicht. Blöcke lohnen nur im klassischen Shell-Modus → OSC-133-basiertes Blocks-lite statt eigenem Block-Renderer.
6. **Commit Context via Gist-Upload widerspricht Local-First.** v1: Transkripte lokal speichern, Commit-Trailer mit lokaler Transcript-ID. Team-Sharing über Cloud wird ein Pro-Feature.
7. **4-Monats-Plan mit allen Features ist unrealistisch** → Core-MVP-Schnitt (vom User bestätigt).

## Repo-Struktur (Symaira-Konvention)

| Repo | Lizenz | Inhalt |
|---|---|---|
| `symaira-terminal` (public) | AGPLv3 | macOS-App komplett, inkl. BYOK. Baut/läuft ohne privaten Code (Regel aus `commercial-boundary.md`). |
| `symaira-terminal-pro` (privat, später) | privat | Go `pro-api` + `pro-worker` auf `symaira-prokit` (Firebase Auth, Stripe, Google Cloud). Features: E2EE-Companion-Relay, gehosteter Tunnel, Commit-Context-Team-Sharing, Workspace-Sync. |

Boundary-Regeln wie bei vault: Pro konsumiert versionierte Releases des Cores; braucht Pro eine Core-Fähigkeit (z. B. E2EE-Sync-Protokoll-Client), wird sie zuerst public implementiert und getaggt. In v1 wird `symaira-terminal-pro` **nicht** gebaut — aber die Modulgrenzen (s. u.) halten die Tür offen.

## Tech-Stack

- **Swift 6** (strict concurrency, Actors), **SwiftUI-Shell + AppKit** wo nötig (Surface-Hosting via `NSViewRepresentable`, Fenster-/Split-Management), **macOS 14+**.
- **Terminal-Engine**: `GhosttyKit.xcframework` via [libghostty-spm](https://swiftpackageregistry.com/Lakr233/libghostty-spm), Version exakt gepinnt. Später optional eigener Build aus gepinntem ghostty-Source (MIT).
- **Kein Web-Stack in v1** (der React-Flow-Canvas kommt erst nach v1 als WKWebView-Overlay).
- Verteilung: **Direct Download + Sparkle + Homebrew Cask**, notarisiert, **kein App Store / keine App Sandbox** (für ein Terminal nicht sinnvoll sandboxbar). Vorhandenes Wissen aus `symaira-vault/docs/macos-notarization.md` wiederverwenden.

## Modulschnitt (lokale SPM-Packages, ein Xcode-Workspace)

```
symaira-terminal/
  App/                      # App-Target: AppKit-Lifecycle, Fenster, Menüs, SwiftUI-Root
  Packages/
    GhosttyBridge/          # EINZIGES Modul mit C-API-Kontakt. TerminalEngine-Protokoll,
                            # Surface-View, Config-Übernahme aus ~/.config/ghostty/config
    TerminalCore/           # PTY-Spawn/Lifecycle, Session-Persistenz (Scrollback, Env, CWD),
                            # OSC-Parser (133, 7, 8, 777, 99/Kitty), Env-Hygiene
    AgentKit/               # Agent-Erkennung (Prozessbaum), Status-Engine,
                            # ACP-Client (JSON-RPC/stdio), opencode-Adapter (serve+SDK)
    WorktreeKit/            # git worktree-Lifecycle, FSEvents-Watching, Diff-Berechnung
    ProviderKit/            # BYOK: Provider-Abstraktion (Anthropic/OpenAI/OpenRouter/
                            # Google/Ollama+OpenAI-kompatibel), Keychain, Streaming,
                            # Modell-Katalog im models.dev-Format
    ContextBank/            # CLAUDE.md/AGENTS.md-Editor-Backend, Rollen-Templates, Rules
    SymairaUI/              # Sidebar, Palette, Status-Ringe, Blocks-lite, Diff-Panel
  docs/                     # ADRs, commercial-boundary.md, bestehendes Research-Doc
```

Abhängigkeitsrichtung: `App → SymairaUI → {AgentKit, WorktreeKit, ProviderKit, ContextBank} → TerminalCore → GhosttyBridge`. ProviderKit und AgentKit kennen GhosttyBridge nicht — Engine bleibt austauschbar (Risiko-Mitigation für libghostty-API-Drift; Notfall-Fallback: SwiftTerm).

## Kernarchitektur-Entscheidungen

### 1. Agent-Integration: Dual-Mode (wichtigste Ergänzung zum Research)
- **PTY-Universalmodus**: Jeder CLI-Agent läuft unverändert im PTY. Status heuristisch: OSC 777/99-Notifications, BEL, Output-Aktivität, Prozesszustand, optional Agent-Hooks (z. B. Claude-Code-Hooks, die OSC 777 emittieren — als Snippet mitliefern).
- **ACP-Modus**: Für ACP-fähige Agenten startet AgentKit den Agenten zusätzlich als ACP-Session (JSON-RPC/stdio). Liefert strukturiert: Permission-Requests (→ nativer Approve-Dialog/Notification statt „blauer Ring raten"), Tool-Call-Timeline, Datei-Diffs. Referenz-Integrationen v1: **OpenCode** (zusätzlich `opencode serve` + SDK als Flaggschiff) und **Gemini CLI**.
- Status-Engine-Zustände: `idle / running / awaitingApproval / error / done`; Quellen-Priorität: ACP > OSC-Notifications > Heuristik.

### 2. BYOK (das Differenzierungs-Feature, ab v1 free)
- Keys ausschließlich im **macOS Keychain**, nie in Config-Dateien, nie an Symaira-Server. Kein Account nötig.
- Genutzt für die terminal-eigenen AI-Features: **„Fehler beheben"-Button** (Exit-Code ≠ 0 via OSC 133), **NL→Command** in der Palette, Output-Zusammenfassung pro Block/Pane.
- **Multi-Account-Routing**: Profile (z. B. „Privat/Anthropic", „Business/OpenRouter") pro Workspace; ProviderKit injiziert die passenden Env-Vars in die PTY-Session und **strippt sie für verschachtelte Sub-Agenten** (`CLAUDECODE`, `ANTHROPIC_API_KEY`, …).

### 3. Blocks-lite statt Warp-Blöcke
- Shell-Integration (zsh/bash/fish-Snippets) emittiert OSC 133 → TerminalCore kennt Command-Zonen + Exit-Codes.
- Features: Cmd+↑/↓-Sprung zwischen Prompts, rote/grüne Markierung am Pane-Rand pro Befehl, „Output kopieren", **„Output an Agent senden"**.
- Kein eigenes Block-Rendering über dem Ghostty-Grid in v1 (hoher Aufwand, nutzlos für TUI-Agenten).

### 4. Worktree-Isolierung
- Task = Branch + transienter Worktree unter `~/Library/Application Support/SymairaTerminal/worktrees/<task-id>/`.
- Lifecycle: anlegen → Agent arbeitet isoliert → Review-Panel (SwiftUI-Diff via FSEvents + `git diff`) → Merge-back oder Verwerfen inkl. Cleanup. Session-Forking = Worktree + Scrollback/Env duplizieren.

### 5. Sicherheit
- Env-Var-Stripping (s. o.), Worktree als primäre Schreib-Isolierung, keine ungefilterten Kontext-Dumps (Context Bank + gezielte Block-Übergabe statt Verzeichnis-Dump).
- Commit Context local-first: Transkript unter App Support, Commit-Trailer mit Transcript-ID. Cloud-Sharing = Pro, später.

## Meilensteine (v1 ≈ 4 Monate)

- **M0 (Woche 1–2)**: Repo-Setup nach Symaira-Konvention (AGENTS.md, commercial-boundary.md, CI), Xcode-Workspace + SPM-Skelett, **Spike: ein GhosttyKit-Surface rendert zsh in SwiftUI-Fenster**. ADR-001: Engine-Wahl + Pin-Strategie.
- **M1 (Monat 1)**: Terminal solide — Tabs/Splits (AppKit), Übernahme von `~/.config/ghostty/config` (Themes/Fonts/Keybindings), Scrollback, Basis-Session-Persistenz. **Gate: Eingabelatenz + Durchsatz-Benchmark ≥ iTerm2-Niveau.**
- **M2 (Monat 2)**: Agent-Awareness — OSC-Parser (133/7/8/777/99), Status-Engine, animierte Pane-Ringe, Workspace-Sidebar (Branch, Ports, Changed Files, letzte Aktivität), Cmd+Shift+U-Fokussprung, Shift-Shift-Palette mit Agent-Presets.
- **M3 (Monat 3)**: Worktree-Manager + Review-Panel, Context Bank (Seitenpanel-Editor für CLAUDE.md/AGENTS.md + Rollen-Templates), **ProviderKit/BYOK** (Keychain, Fix-Error, NL→Command), **ACP-Client** mit OpenCode + Gemini CLI.
- **M4 (Monat 4)**: Blocks-lite, Multi-Account-Routing, Polish (Onboarding, Settings), Notarisierung + Sparkle + Homebrew Cask, **Public Beta + OSS-Launch (AGPLv3)**.
- **Post-v1**: Workflow-Canvas (WKWebView/React Flow), Mobile Companion + E2EE-Relay (`-pro`), gehosteter Tunnel (`-pro`), Commit-Context-Team-Sharing (`-pro`), STT/Sketchpad, WKWebView-Browser-Pane mit Browser-MCP.

## Verifikation

- **Pro Milestone manuell mit echten Agenten testen**: Claude Code, OpenCode, Aider, Gemini CLI parallel in 4 Panes; TUI-Rendering, Statuswechsel, Approval-Erkennung.
- **Performance-Gate (M1)**: Tipplatenz-Messung + `cat` großer Logs/Build-Output-Durchsatz vs. Ghostty/iTerm2; Speicher unter Last.
- **XCTests**: OSC-Parser (Fixture-Streams inkl. 133-Sequenzen), Status-Engine-Übergänge, Worktree-Lifecycle (Temp-Repos), ProviderKit (Keychain-Mock, Streaming-Stubs).
- **VT-Konformität**: Stichproben mit vttest — Engine liefert Konformität, Bridge darf nichts verschlucken.
- **Boundary-Check**: Public Repo baut ohne jegliche Pro-/Cloud-Abhängigkeit (`xcodebuild` in CI auf GitHub Actions, macOS-Runner).

## Risiken

1. **libghostty-API-Drift** → Pin + GhosttyBridge-Isolation + SwiftTerm-Fallback-Pfad.
2. **ACP-Verhalten variiert je Agent** → v1 nur 2 Referenz-Integrationen, PTY-Modus bleibt immer der Fallback.
3. **Solo-Dev + 4 Monate ist sportlich** → Meilensteine sind so geschnitten, dass nach M2 bereits ein nutzbares „agent-aware Terminal" existiert (notfalls früherer Beta-Launch ohne M3/M4-Features).
