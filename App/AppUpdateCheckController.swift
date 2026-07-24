import Foundation
import AppKit

// MARK: - Types (mirror of symaira-appkit's SymairaUpdateCheck)

public struct ReleaseInfo: Sendable, Equatable {
    public let tagName: String
    public let htmlURL: String
    public init(tagName: String, htmlURL: String) {
        self.tagName = tagName
        self.htmlURL = htmlURL
    }
}

public enum AppUpdateStatus: Equatable, Sendable {
    case unknown
    case upToDate
    case available(ReleaseInfo)
    case skipped(ReleaseInfo)
    case error(String)
}

/// UserDefaults-backed store for the user's "skip this version" preference.
final class UserDefaultsSkippedVersionStore: Sendable {
    private let key: String
    init(key: String) { self.key = key }
    func skippedTag() -> String? { UserDefaults.standard.string(forKey: key) }
    func setSkippedTag(_ tag: String?) {
        if let tag {
            UserDefaults.standard.set(tag, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

/// Never-blocking GitHub release checker with disk-cache (24h TTL).
final class UpdateChecker: Sendable {
    private let owner: String
    private let repo: String
    private let cacheTTL: TimeInterval
    private let cacheDir: URL

    init(owner: String, repo: String, cacheTTL: TimeInterval = 86400) {
        self.owner = owner
        self.repo = repo
        self.cacheTTL = cacheTTL
        self.cacheDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/symaira-terminal", isDirectory: true)
    }

    func check(currentVersion: String) async throws -> ReleaseInfo? {
        guard let current = StableVersion(currentVersion) else { return nil }
        let latest = try await fetchLatest()
        guard let latestVersion = StableVersion(latest.tagName), latestVersion > current else { return nil }
        return ReleaseInfo(tagName: latest.tagName, htmlURL: latest.htmlURL)
    }

    private struct LatestRelease: Codable {
        let tagName: String
        let htmlURL: String
        var fetchedAt: Date?
    }

    private func fetchLatest() async throws -> LatestRelease {
        // Check cache first
        if let cached = readCache() { return cached }

        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("symaira-terminal/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0")", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateCheckError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        struct GitHubRelease: Decodable {
            let tagName: String
            let htmlUrl: String
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let release = try? decoder.decode(GitHubRelease.self, from: data) else {
            throw UpdateCheckError.decodeFailed
        }
        let result = LatestRelease(tagName: release.tagName, htmlURL: release.htmlUrl, fetchedAt: Date())
        writeCache(result)
        return result
    }

    private var cacheFile: URL { cacheDir.appendingPathComponent("latest-release.json") }

    private func readCache() -> LatestRelease? {
        guard let data = try? Data(contentsOf: cacheFile),
              let entry = try? JSONDecoder().decode(LatestRelease.self, from: data),
              let fetchedAt = entry.fetchedAt,
              Date().timeIntervalSince(fetchedAt) < cacheTTL
        else { return nil }
        return entry
    }

    private func writeCache(_ entry: LatestRelease) {
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entry) {
            try? data.write(to: cacheFile, options: .atomic)
        }
    }
}

enum UpdateCheckError: Error, Sendable {
    case httpStatus(Int)
    case decodeFailed
}

/// Minimal semver parsing for stable tags (e.g. "v0.8.3" → 0.8.3).
struct StableVersion: Comparable, Sendable {
    let major: Int; let minor: Int; let patch: Int
    init?(_ tag: String) {
        let s = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let parts = s.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 3 else { return nil }
        self.major = parts[0]; self.minor = parts[1]; self.patch = parts[2]
    }
    static func < (lhs: StableVersion, rhs: StableVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

/// High-level controller: ObservableObject that drives the update check
/// and exposes the status for SwiftUI/AppKit views.
@MainActor
final class AppUpdateCheckController: ObservableObject {
    @Published private(set) var status: AppUpdateStatus = .unknown
    private let checker: UpdateChecker
    private let store: UserDefaultsSkippedVersionStore

    init() {
        self.checker = UpdateChecker(owner: "danieljustus", repo: "symaira-terminal")
        self.store = UserDefaultsSkippedVersionStore(key: "com.symaira.terminal.updateSkippedTag")
    }

    func checkForUpdate() {
        Task { [weak self] in
            guard let self else { return }
            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
            do {
                if let release = try await checker.check(currentVersion: currentVersion) {
                    let status: AppUpdateStatus
                    if store.skippedTag() == release.tagName {
                        status = .skipped(release)
                    } else {
                        status = .available(release)
                    }
                    await MainActor.run { self.status = status }
                } else {
                    await MainActor.run { self.status = .upToDate }
                }
            } catch {
                await MainActor.run { self.status = .error(String(describing: error)) }
            }
        }
    }

    func skipCurrentVersion() {
        if case .available(let release) = status {
            store.setSkippedTag(release.tagName)
            status = .skipped(release)
        }
    }

    func openReleasePage() {
        guard case .available(let release) = status,
              let url = URL(string: release.htmlURL)
        else { return }
        NSWorkspace.shared.open(url)
    }
}
