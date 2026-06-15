import Foundation
import TerminalCore
import AgentKit
import UserNotifications

@MainActor
final class OSCEventHandler {
    /// Hard cap on the length of a title that originates from terminal output.
    /// OSC titles are attacker-controllable (any program, remote SSH session, or
    /// `cat`-ed file can emit them), so an unbounded string must never reach the
    /// window/tab UI.
    private static let maxTitleLength = 256
    /// Minimum spacing between two terminal-triggered notifications. Without
    /// this, output containing many OSC 9 sequences could spam the user.
    private static let notificationMinInterval: TimeInterval = 3.0

    private var statusEngines: [UUID: AgentStatusEngine] = [:]
    private var paneTitles: [UUID: String] = [:]
    private var paneCWDs: [UUID: URL] = [:]
    private var lastNotificationAt: Date?
    private var didRequestNotificationAuth = false

    var onStatusChanged: ((UUID, AgentStatus) -> Void)?
    var onTitleChanged: ((UUID, String) -> Void)?
    var onCWDChanged: ((UUID, URL) -> Void)?
    var onNotification: ((String, String) -> Void)?

    func handle(_ event: OSCEvent, for paneID: UUID) {
        switch event {
        case .windowTitle(let title):
            let clean = Self.sanitizeTitle(title)
            paneTitles[paneID] = clean
            onTitleChanged?(paneID, clean)

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

    /// The terminal-provided title for a pane, or "" if none has arrived yet.
    /// Callers decide their own placeholder (window: app name; tab: "Tab N"),
    /// so we never surface a directory-derived default before a real OSC title.
    func title(for paneID: UUID) -> String {
        paneTitles[paneID] ?? ""
    }

    func cwd(for paneID: UUID) -> URL? {
        paneCWDs[paneID]
    }

    private func sendNotification(title: String, body: String) {
        // Rate-limit: terminal output can emit OSC 9 notifications in a tight
        // loop; drop anything that arrives faster than the minimum interval.
        let now = Date()
        if let last = lastNotificationAt, now.timeIntervalSince(last) < Self.notificationMinInterval {
            return
        }
        lastNotificationAt = now

        // These strings come from untrusted terminal output, so bound their
        // length and strip control characters, and label the source so a
        // notification cannot impersonate the app or the system.
        let safeTitle = Self.sanitizeTitle(title)
        let safeBody = Self.sanitizeTitle(body)
        onNotification?(safeTitle, safeBody)

        let alreadyAuthorized = didRequestNotificationAuth
        didRequestNotificationAuth = true

        // Capture only Sendable Strings across the concurrency boundary; the
        // UserNotifications objects are rebuilt on the target side.
        if alreadyAuthorized {
            Self.deliver(title: safeTitle, body: safeBody)
        } else {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                guard granted else { return }
                Self.deliver(title: safeTitle, body: safeBody)
            }
        }
    }

    private static func deliver(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = "Terminal: \(title)"
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Strip control characters and clamp the length of a string that came from
    /// untrusted terminal output before it is shown in the UI or a notification.
    static func sanitizeTitle(_ raw: String) -> String {
        let stripped = raw.unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) }
        var result = String(String.UnicodeScalarView(stripped))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if result.count > maxTitleLength {
            result = String(result.prefix(maxTitleLength))
        }
        return result
    }
}
