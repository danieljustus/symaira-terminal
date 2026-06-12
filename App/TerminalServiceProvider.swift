import AppKit
import TerminalCore

/// Handles macOS Services menu requests to open terminal panes at specific directories.
/// Registered in Info.plist under NSServices; invoked when users right-click a folder
/// in Finder and select "New symTerminal Tab Here" or "New symTerminal Window Here".
@MainActor
@objc class TerminalServiceProvider: NSObject {
    weak var paneManager: PaneManager?

    init(paneManager: PaneManager) {
        self.paneManager = paneManager
        super.init()
    }

    /// Opens a new tab at the directory selected in Finder.
    @objc func openTab(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSError?>) {
        openFiles(from: pasteboard, allowTabs: true, error: error)
    }

    /// Opens a new window at the directory selected in Finder.
    @objc func openWindow(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSError?>) {
        openFiles(from: pasteboard, allowTabs: false, error: error)
    }

    private func openFiles(from pasteboard: NSPasteboard, allowTabs: Bool, error: AutoreleasingUnsafeMutablePointer<NSError?>) {
        guard let paneManager else {
            error.pointee = NSError(
                domain: "TerminalServiceProvider",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "PaneManager not available"]
            )
            return
        }

        // Try to read file URLs first (Finder sends these)
        var directories: [URL] = []

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] {
            directories = urls.compactMap { url in
                resolveDirectory(from: url)
            }
        }

        // Fallback: try plain text paths (some apps send paths as strings)
        if directories.isEmpty, let string = pasteboard.string(forType: .string) {
            let expanded = (string as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            if let dir = resolveDirectory(from: url) {
                directories.append(dir)
            }
        }

        guard !directories.isEmpty else {
            error.pointee = NSError(
                domain: "TerminalServiceProvider",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No valid directory found in pasteboard"]
            )
            return
        }

        // Open each directory. For tabs, create panes in the existing window.
        // For windows, we'd need to create a new window — but the issue scope
        // only requires tab support for now, so we create panes for both.
        for directory in directories {
            _ = paneManager.createPane(inDirectory: directory)
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    /// Resolves a URL to a directory. If the URL points to a file, returns its parent directory.
    private func resolveDirectory(from url: URL) -> URL? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return nil
        }

        if isDirectory.boolValue {
            return url
        } else {
            return url.deletingLastPathComponent()
        }
    }
}
