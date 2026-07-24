import Foundation
import Testing
@testable import SymairaUI

@Suite struct OnboardingCompletionTests {
    /// Scratch defaults so the tests never touch the user's real preferences.
    @MainActor private func makeDefaults() -> UserDefaults {
        let suite = "OnboardingCompletionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test @MainActor func freshInstallIsNotCompleted() {
        let defaults = makeDefaults()
        #expect(OnboardingView.isCompleted(in: defaults) == false)
    }

    @Test @MainActor func markCompletedIsObservedByIsCompleted() {
        let defaults = makeDefaults()
        OnboardingView.markCompleted(in: defaults)
        #expect(OnboardingView.isCompleted(in: defaults))
    }

    /// The window-close path and the in-view buttons must agree on one key, so
    /// dismissing the welcome window cannot leave the flow reappearing forever.
    @Test @MainActor func completionKeyIsStable() {
        let defaults = makeDefaults()
        OnboardingView.markCompleted(in: defaults)
        #expect(defaults.bool(forKey: OnboardingView.completedDefaultsKey))
    }
}
