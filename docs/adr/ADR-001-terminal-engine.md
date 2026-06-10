# ADR-001: Terminal-Engine — libghostty via GhosttyKit, gepinnt, hinter Protokoll isoliert

Status: akzeptiert (2026-06-10)

## Kontext

Das Terminal muss auf dem Mac nativ wirken, 120 fps/ProMotion-flüssig rendern und
dichte Agent-Output-Ströme (Build-Logs, TUI-Agenten wie Claude Code/OpenCode im
Alternate Screen) ohne Latenz verarbeiten. Web-Renderer (xterm.js/Electron) sind per
Anti-Pattern-Beschluss ausgeschlossen.

Kandidaten:

1. **libghostty / GhosttyKit** (Zig, Metal-Pipeline, VT-Parser + Grid + Font
   Shaping; MIT). Offizieller Status Juni 2026: Kern produktionserprobt (treibt
   Ghostty.app), aber „API signatures in flux" — keine Stabilitätsgarantie.
   Verfügbar als prebuilt `GhosttyKit.xcframework` über das Swift Package
   [`Lakr233/libghostty-spm`](https://github.com/Lakr233/libghostty-spm)
   (Community-Build aus gepinntem ghostty-Source; gleiche Einbettung wie
   Ghostty.app selbst und cmux).
2. **SwiftTerm** (reines Swift, CoreGraphics/Metal-optional). Stabile API, aber
   deutlich langsamer bei hohem Durchsatz, weniger VT-Konformität, kein Ghostty-
   Config-Ökosystem.
3. **Eigener VT-Parser/Renderer** — ausgeschlossen (Jahre Arbeit, kein Mehrwert).

## Entscheidung

- **libghostty via `libghostty-spm`**, Version **exakt gepinnt** (kein `from:`,
  sondern `exact:` im Package.swift). Upgrades sind bewusste, getestete Schritte.
- **Alle C-API-Aufrufe leben ausschließlich im Target `GhosttyBridge`.** Der Rest
  der App programmiert gegen das Swift-Protokoll `TerminalEngine` /
  `TerminalSurfaceHosting`. Bei API-Drift wird genau ein Target angefasst.
- **Fallback-Pfad**: Sollte libghostty unbrauchbar werden (Lizenz-/API-/
  Maintenance-Risiko), wird `GhosttyBridge` durch ein SwiftTerm-Backend ersetzt.
  Das Protokoll ist deshalb engine-neutral formuliert (keine Ghostty-Typen in der
  öffentlichen Schnittstelle).
- **Später optional**: eigener GhosttyKit-Build aus gepinntem ghostty-Source statt
  Community-Prebuild (Supply-Chain-Härtung vor 1.0; Checksumme des binaryTarget
  wird ohnehin von SPM verifiziert).

## Konsequenzen

- Wir erben Ghostty-Features gratis: VT-Konformität, Font-Shaping/Ligaturen,
  Theme-/Config-Kompatibilität mit `~/.config/ghostty/config`.
- Wir tragen das Risiko instabiler API-Signaturen — gekapselt in einem Target.
- Blocks-Rendering im Warp-Stil (eigene Views pro Befehl) ist mit dem Ghostty-Grid
  nicht trivial; bewusste Entscheidung für OSC-133-basiertes „Blocks-lite"
  (siehe Architekturplan).
