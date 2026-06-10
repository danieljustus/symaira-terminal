// M0 smoke check: proves the full pipeline end-to-end without eyeballs —
//
//   GhosttyEngine → GhosttySurfaceController → host PTY (zsh)
//   keystrokes → PTY → zsh output → ghostty VT/Metal grid → readViewportText
//
// Run: swift run TerminalSmoke   (exits 0 when the echoed marker appears on
// the rendered grid, 1 otherwise). Requires a GUI session (Metal surface).

import AppKit
import GhosttyBridge
import TerminalCore

let marker = "SYMAIRA_SMOKE_\(Int.random(in: 1000...9999))"

@MainActor
final class SmokeDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var surface: GhosttySurfaceController?

    func applicationDidFinishLaunching(_: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        self.window = window

        do {
            let engine = GhosttyEngine()
            print("engine: \(engine.engineDescription)")
            let surface = try engine.makeSurface(configuration: TerminalSurfaceConfiguration())
            guard let ghostty = surface as? GhosttySurfaceController else {
                fail("unexpected surface type")
            }
            self.surface = ghostty
            ghostty.view.frame = window.contentLayoutRect
            window.contentView = ghostty.view
            window.orderFrontRegardless()
        } catch {
            fail("surface creation failed: \(error)")
        }

        // Give zsh time to start, type the marker, then read the grid back.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            self.surface?.sendText("echo \(marker)\n")
            try? await Task.sleep(for: .seconds(2))
            guard let text = self.surface?.readViewportText() else {
                fail("viewport read returned nil")
            }
            // The marker must appear as command OUTPUT (own line), not merely
            // as the echoed keystroke after the prompt.
            let outputLines = text.split(separator: "\n").filter {
                $0.trimmingCharacters(in: .whitespaces) == marker
            }
            print("--- viewport ---\n\(text)\n----------------")
            if outputLines.isEmpty {
                fail("marker not found in rendered viewport")
            } else {
                print("SMOKE OK — zsh runs, grid renders, I/O loop works")
                self.surface?.close()
                exit(0)
            }
        }
    }
}

@MainActor
func fail(_ message: String) -> Never {
    print("SMOKE FAILED — \(message)")
    exit(1)
}

let app = NSApplication.shared
let delegate = SmokeDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // no Dock icon for the smoke run
app.run()
