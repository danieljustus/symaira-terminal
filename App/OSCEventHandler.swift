import Foundation
import TerminalCore
import AgentKit

@MainActor
final class OSCEventHandler {
    private var statusEngines: [UUID: AgentStatusEngine] = [:]
    private var paneTitles: [UUID: String] = [:]
    private var paneCWDs: [UUID: URL] = [:]

    var onStatusChanged: ((UUID, AgentStatus) -> Void)?
    var onTitleChanged: ((UUID, String) -> Void)?
    var onCWDChanged: ((UUID, URL) -> Void)?
    var onNotification: ((String, String) -> Void)?

    func handle(_ event: OSCEvent, for paneID: UUID) {
        switch event {
        case .windowTitle(let title):
            paneTitles[paneID] = title
            onTitleChanged?(paneID, title)

        case .workingDirectory(let url):
            paneCWDs[paneID] = url
            onCWDChanged?(paneID, url)

        case .semanticPrompt(let prompt):
            handleSemanticPrompt(prompt, for: paneID)

        case .notification(let title, let body):
            sendNotification(title: title, body: body)

        case .hyperlink:
            break

        case .unhandled:
            break
        }
    }

    private func handleSemanticPrompt(_ prompt: SemanticPromptEvent, for paneID: UUID) {
        var engine = statusEngines[paneID] ?? AgentStatusEngine()
        switch prompt {
        case .promptStart:
            engine.apply(StatusObservation(.idle, source: .osc))
        case .commandStart:
            engine.apply(StatusObservation(.running, source: .osc))
        case .outputStart:
            engine.apply(StatusObservation(.running, source: .osc))
        case .commandEnd(let exitCode):
            if let code = exitCode {
                engine.processExited(code: Int32(code))
            } else {
                engine.apply(StatusObservation(.done, source: .osc))
            }
        }
        statusEngines[paneID] = engine
        onStatusChanged?(paneID, engine.current)
    }

    func processExited(for paneID: UUID, code: Int32) {
        var engine = statusEngines[paneID] ?? AgentStatusEngine()
        engine.processExited(code: code)
        statusEngines[paneID] = engine
        onStatusChanged?(paneID, engine.current)
    }

    func status(for paneID: UUID) -> AgentStatus {
        statusEngines[paneID]?.current ?? .idle
    }

    func title(for paneID: UUID) -> String {
        paneTitles[paneID] ?? "Terminal"
    }

    func cwd(for paneID: UUID) -> URL? {
        paneCWDs[paneID]
    }

    private func sendNotification(title: String, body: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = body
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
        onNotification?(title, body)
    }
}
