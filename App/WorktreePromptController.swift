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
    /// successful, or `nil` if the user cancelled or input was empty.
    @discardableResult
    func promptForWorktree(
        worktreeStore: WorktreeStore,
        create: (String) throws -> Worktree
    ) -> Worktree? {
        let alert = buildPromptAlert()
        activeAlert = alert
        defer { activeAlert = nil }

        let response = alertRunner?(alert) ?? alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }

        let taskID = promptInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !taskID.isEmpty else { return nil }

        do {
            return try create(taskID)
        } catch {
            let errorAlert = NSAlert(error: error)
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

    private func buildPromptAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Create New Worktree"
        alert.informativeText = "Enter task ID (alphanumeric only):"
        alert.accessoryView = promptInput
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        return alert
    }
}
