import Foundation
import AppKit
import SymairaUpdateCheck

/// Thin adapter around symaira-appkit's AppUpdateChecker that adds
/// terminal-specific behaviour (openReleasePage) and convenience wrappers.
@MainActor
final class AppUpdateCheckController: ObservableObject {
    @Published private(set) var status: AppUpdateStatus = .unknown

    private let checker: AppUpdateChecker

    init() {
        let updateChecker = UpdateChecker(owner: "danieljustus", repo: "symaira-terminal")
        let store = UserDefaultsSkippedVersionStore(key: "com.symaira.terminal.updateSkippedTag")
        self.checker = AppUpdateChecker(
            checker: updateChecker,
            store: store,
            currentVersion: {
                Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
            }
        )
    }

    func checkForUpdate() {
        Task { [weak self] in
            guard let self else { return }
            await checker.checkForUpdate()
            await MainActor.run { self.status = checker.status }
        }
    }

    func skipCurrentVersion() {
        if case .available(let release) = checker.status {
            checker.skip(release)
            status = checker.status
        }
    }

    func openReleasePage() {
        if case .available(let release) = checker.status,
           let url = URL(string: release.htmlURL) {
            NSWorkspace.shared.open(url)
        }
    }
}
