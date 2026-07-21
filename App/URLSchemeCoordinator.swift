import Foundation

/// Coordinates URL-scheme parsing and command dispatch.
///
/// Wraps `URLSchemeHandler.parse` and the `switch command` dispatch that
/// formerly lived inline in `AppDelegate.application(_:open:)`.
@MainActor
final class URLSchemeCoordinator {
    private let handler: URLSchemeHandler

    init(handler: URLSchemeHandler = URLSchemeHandler()) {
        self.handler = handler
    }

    /// Parse each URL and dispatch the resulting command to `paneManager`.
    /// URLs that fail to parse or return nil are silently skipped — matching
    /// the original AppDelegate behaviour.
    func dispatch(urls: [URL], paneManager: PaneManager) {
        for url in urls {
            guard let command = handler.parse(url) else { continue }
            execute(command, paneManager: paneManager)
        }
    }

    // MARK: - Private

    private func execute(_ command: URLSchemeCommand, paneManager: PaneManager) {
        switch command {
        case .openDirectory(let directory):
            _ = paneManager.createPane(inDirectory: directory)

        case .openTab(let command, let workingDirectory):
            if let command, !command.isEmpty {
                Task {
                    _ = await paneManager.openTab(
                        command: command,
                        workingDirectory: workingDirectory,
                        origin: .urlScheme
                    )
                }
            } else if let workingDirectory {
                _ = paneManager.createPane(inDirectory: workingDirectory)
            } else {
                _ = paneManager.createPane()
            }
        }
    }
}
