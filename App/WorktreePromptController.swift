import AppKit
import WorktreeKit
import SymairaUI

/// Drives the NSAlert-based worktree-creation task-ID prompt flow.
///
/// Formerly inlined inside the `onCreateWorktree` closure of `WorkspaceSidebar`
/// within `AppDelegate.applicationDidFinishLaunching`.
@MainActor
final class WorktreePromptController {
    /// The active prompt window, if any. Prevents multiple alerts from stacking.
    private var activeAlert: NSAlert?

    /// Injectable alert runner — returns the `NSApplication.ModalResponse` from
    /// `alert.runModal()`. Defaults to the real `NSAlert.runModal()`. Override
    /// in tests to avoid presenting UI.
    var alertRunner: ((NSAlert) -> NSApplication.ModalResponse)?

    init(alertRunner: ((NSAlert) -> NSApplication.ModalResponse)? = nil) {
        self.alertRunner = alertRunner
    }

    /// Show the task-ID prompt. On success the worktree is created via `create`.
    /// On failure an error alert is shown. Returns the created `Worktree` if
    /// successful, or `nil` if the user cancelled or input was invalid.
    @discardableResult
    func promptForWorktree(
        worktreeStore: WorktreeStore,
        create: (String) throws -> Worktree
    ) -> Worktree? {
        // Validate the repository exists and is a git repo before showing the
        // prompt. This catches the non-git cwd case early with a clear error.
        guard worktreeStore.isGitRepository() else {
            let repoAlert = NSAlert()
            repoAlert.alertStyle = .critical
            repoAlert.messageText = "Cannot Create Worktree"
            repoAlert.informativeText = "The current working directory is not a git repository. Open a project folder that contains a git repository first."
            repoAlert.addButton(withTitle: "OK")
            _ = alertRunner?(repoAlert) ?? repoAlert.runModal()
            return nil
        }

        let alert = buildPromptAlert(repoName: worktreeStore.repositoryName)
        activeAlert = alert
        defer { activeAlert = nil }

        let response = alertRunner?(alert) ?? alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }

        let taskID = promptInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !taskID.isEmpty else {
            let errorAlert = NSAlert()
            errorAlert.alertStyle = .warning
            errorAlert.messageText = "Invalid Task ID"
            errorAlert.informativeText = "Task ID cannot be empty."
            errorAlert.addButton(withTitle: "OK")
            _ = alertRunner?(errorAlert) ?? errorAlert.runModal()
            return nil
        }

        // Validate format before attempting creation.
        if case .failure(let error) = worktreeStore.validateTaskID(taskID) {
            let errorAlert = NSAlert()
            errorAlert.alertStyle = .warning
            errorAlert.messageText = "Invalid Task ID"
            errorAlert.informativeText = error.errorDescription ?? "The task ID contains invalid characters."
            errorAlert.addButton(withTitle: "OK")
            _ = alertRunner?(errorAlert) ?? errorAlert.runModal()
            return nil
        }

        do {
            return try create(taskID)
        } catch {
            let errorAlert = NSAlert(error: error)
            errorAlert.alertStyle = .critical
            _ = alertRunner?(errorAlert) ?? errorAlert.runModal()
            return nil
        }
    }

    // MARK: - Internal (exposed for testing)

    /// The text field used to capture the task ID.
    private(set) lazy var promptInput: NSTextField = {
        NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
    }()

    // MARK: - Private

    private func buildPromptAlert(repoName: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Create New Worktree"
        alert.informativeText = "Repository: \(repoName)\n\nEnter task ID (alphanumeric only):"
        alert.accessoryView = promptInput
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        return alert
    }
}
