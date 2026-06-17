import Foundation
import IOKit
import IOKit.pwr_mgt

@MainActor
public final class SleepPreventionManager: ObservableObject {
    public static let shared = SleepPreventionManager()

    @Published public private(set) var isAssertionActive: Bool = false

    private var assertionID: IOPMAssertionID = 0
    private var hasActiveAgent: Bool = false

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    @objc private func settingsChanged() {
        updateAssertionState()
    }

    public func updateAgentActivityState(hasActiveAgent: Bool) {
        self.hasActiveAgent = hasActiveAgent
        updateAssertionState()
    }

    public func updateAssertionState() {
        let keepAwakeAlways = UserDefaults.standard.object(forKey: "keepAwakeAlways") as? Bool ?? false
        let keepAwakeWhileAgentRunning = UserDefaults.standard.object(forKey: "keepAwakeWhileAgentRunning") as? Bool ?? true

        let shouldBeActive = keepAwakeAlways || (keepAwakeWhileAgentRunning && hasActiveAgent)

        if shouldBeActive && !isAssertionActive {
            activateAssertion()
        } else if !shouldBeActive && isAssertionActive {
            deactivateAssertion()
        }
    }

    private func activateAssertion() {
        let reason = "Symaira Terminal is active or running background tasks" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoIdleSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )

        if result == kIOReturnSuccess {
            isAssertionActive = true
            NSLog("Symaira Terminal: Sleep prevention assertion activated (ID: \(assertionID))")
        } else {
            NSLog("Symaira Terminal: Failed to create sleep prevention assertion (Error: \(result))")
        }
    }

    public func deactivateAssertion() {
        guard isAssertionActive else { return }
        let result = IOPMAssertionRelease(assertionID)
        if result == kIOReturnSuccess {
            isAssertionActive = false
            assertionID = 0
            NSLog("Symaira Terminal: Sleep prevention assertion released")
        } else {
            NSLog("Symaira Terminal: Failed to release sleep prevention assertion (Error: \(result))")
        }
    }
}
