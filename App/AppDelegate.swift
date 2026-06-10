import AppKit
import GhosttyBridge
import TerminalCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var engine: GhosttyEngine?
    private var surface: (any TerminalCore.TerminalSurface)?
    private var oscParser = OSCStreamParser()

    func applicationDidFinishLaunching(_: Notification) {
        let engine = GhosttyEngine()
        self.engine = engine

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Symaira Terminal — M0 Spike"
        window.contentMinSize = NSSize(width: 480, height: 320)
        window.center()

        do {
            let surface = try engine.makeSurface(configuration: TerminalSurfaceConfiguration())
            self.surface = surface

            // M0 smoke check for the agent-awareness tap: OSC events from the
            // live PTY stream land in the host. Becomes the status engine feed.
            surface.outputTap = { bytes in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    for event in self.oscParser.feed(bytes) {
                        NSLog("symaira osc event: \(String(describing: event))")
                    }
                }
            }

            let contentView = NSView(frame: window.contentLayoutRect)
            surface.view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(surface.view)
            NSLayoutConstraint.activate([
                surface.view.topAnchor.constraint(equalTo: contentView.topAnchor),
                surface.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                surface.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                surface.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            ])
            window.contentView = contentView
            window.makeFirstResponder(surface.view)
        } catch {
            NSLog("failed to create terminal surface: \(error)")
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_: Notification) {
        surface?.close()
    }
}
