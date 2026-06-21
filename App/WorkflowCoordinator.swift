import AppKit
import SwiftUI
import SymairaUI
import WorktreeKit

/// Manages the workflow canvas window and handoff pipeline.
/// Extracted from AppDelegate to improve testability and reduce file size.
@MainActor
final class WorkflowCoordinator {
    private var canvasWindow: NSWindow?
    private weak var paneManager: PaneManager?
    private weak var sidebarViewModel: SidebarViewModel?

    init(paneManager: PaneManager?, sidebarViewModel: SidebarViewModel?) {
        self.paneManager = paneManager
        self.sidebarViewModel = sidebarViewModel
    }

    func setupObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRunWorkflow(_:)),
            name: Notification.Name("com.symaira.terminal.runWorkflow"),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHandoffNotification(_:)),
            name: NSNotification.Name("com.symaira.terminal.handoff"),
            object: nil
        )
    }

    func showWorkflowCanvas() {
        if let existing = canvasWindow {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let view = WorkflowCanvasView()
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.title = "Workflow Canvas"
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        canvasWindow = window
    }

    @objc private func handleRunWorkflow(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let workflowJSON = userInfo["workflow"] as? String,
              let data = workflowJSON.data(using: .utf8),
              let workflow = try? JSONDecoder().decode(WorkflowData.self, from: data) else {
            return
        }

        let targetNodeIDs = Set(workflow.edges.map(\.target))
        let startingNodes = workflow.nodes.filter { !targetNodeIDs.contains($0.id) }

        guard let nodeToRun = startingNodes.first ?? workflow.nodes.first else { return }
        runNode(nodeToRun)
    }

    @objc private func handleHandoffNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let taskID = userInfo["taskID"] as? String else {
            return
        }

        let summary = userInfo["summary"] as? String ?? ""

        guard let savedWorkflowJSON = UserDefaults.standard.string(forKey: "symaira.workflow.canvas"),
              let data = savedWorkflowJSON.data(using: .utf8),
              let workflow = try? JSONDecoder().decode(WorkflowData.self, from: data),
              let sourceNode = workflow.nodes.first(where: { $0.data.path == taskID }) else {
            return
        }

        let edgesFromSource = workflow.edges.filter { $0.source == sourceNode.id }
        let targetNodeNames = edgesFromSource.compactMap { edge -> String? in
            guard let targetNode = workflow.nodes.first(where: { $0.id == edge.target }) else { return nil }
            return targetNode.data.label ?? targetNode.data.path ?? "Unknown"
        }

        showHandoffConfirmation(
            sourceName: sourceNode.data.label ?? sourceNode.data.path ?? "Unknown",
            targetNames: targetNodeNames,
            summary: summary
        ) { [weak self] approved in
            guard approved, let self = self else { return }

            self.updateNodeStatus(nodeID: sourceNode.id, status: "done")

            for edge in edgesFromSource {
                guard let targetNode = self.workflowNodes(workflow)?.first(where: { $0.id == edge.target }) else { continue }
                self.executeHandoff(from: sourceNode, to: targetNode, summary: summary)
            }
        }
    }

    private func workflowNodes(_ workflow: WorkflowData) -> [WorkflowNode]? {
        workflow.nodes
    }

    private func showHandoffConfirmation(
        sourceName: String,
        targetNames: [String],
        summary: String,
        completion: @escaping (Bool) -> Void
    ) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Handoff Request"
            alert.informativeText = """
                A notification requests a workflow handoff.

                Source: \(sourceName)
                Target(s): \(targetNames.joined(separator: ", "))
                \(summary.isEmpty ? "" : "Summary: \(summary)")

                Do you want to proceed?
                """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Allow")
            alert.addButton(withTitle: "Deny")

            let response = alert.runModal()
            completion(response == .alertFirstButtonReturn)
        }
    }

    private func executeHandoff(from sourceNode: WorkflowNode, to targetNode: WorkflowNode, summary: String) {
        guard let worktreeStore = sidebarViewModel?.worktreeStore,
              let paneManager = paneManager,
              let worktreeManager = paneManager.worktreeManager else {
            return
        }

        guard let sourceWT = worktreeStore.worktrees.first(where: { $0.taskID == sourceNode.data.path }) else {
            return
        }

        do {
            let package = try worktreeManager.createHandoffPackage(from: sourceWT)

            let targetPath = targetNode.data.path ?? "task-\(UUID().uuidString.prefix(8))"
            let targetWT: Worktree
            if let existing = worktreeStore.worktrees.first(where: { $0.taskID == targetPath }) {
                targetWT = existing
            } else {
                targetWT = try worktreeStore.create(taskID: targetPath)
            }

            try worktreeManager.applyHandoffPackage(package, to: targetWT)

            let newPane = paneManager.createPane(inDirectory: targetWT.path)

            if let prompt = targetNode.data.prompt, !prompt.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    newPane.surface?.sendText(prompt + "\n")
                }
            }

            updateNodeStatus(nodeID: targetNode.id, status: "active")
        } catch {
            NSLog("symaira: handoff failed: \(error.localizedDescription)")
        }
    }

    private func runNode(_ node: WorkflowNode) {
        guard let worktreeStore = sidebarViewModel?.worktreeStore,
              let paneManager = paneManager else {
            return
        }

        let path = node.data.path ?? "task-\(UUID().uuidString.prefix(8))"
        let wt: Worktree
        do {
            if let existing = worktreeStore.worktrees.first(where: { $0.taskID == path }) {
                wt = existing
            } else {
                wt = try worktreeStore.create(taskID: path)
            }

            let pane = paneManager.createPane(inDirectory: wt.path)

            if let prompt = node.data.prompt, !prompt.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    pane.surface?.sendText(prompt + "\n")
                }
            }

            updateNodeStatus(nodeID: node.id, status: "active")
        } catch {
            NSLog("symaira: failed to run workflow node: \(error.localizedDescription)")
        }
    }

    private func updateNodeStatus(nodeID: String, status: String) {
        NotificationCenter.default.post(
            name: Notification.Name("com.symaira.terminal.updateCanvasNodeStatus"),
            object: nil,
            userInfo: ["nodeID": nodeID, "status": status]
        )
    }
}

// MARK: - Workflow Codable Models

struct WorkflowData: Codable {
    let nodes: [WorkflowNode]
    let edges: [WorkflowEdge]
}

struct WorkflowNode: Codable {
    let id: String
    let data: WorkflowNodeData
}

struct WorkflowNodeData: Codable {
    let label: String?
    let type: String?
    let prompt: String?
    let path: String?
    let model: String?
}

struct WorkflowEdge: Codable {
    let id: String
    let source: String
    let target: String
}
