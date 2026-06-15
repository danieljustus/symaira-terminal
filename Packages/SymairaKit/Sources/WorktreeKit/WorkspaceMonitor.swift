import Foundation

/// Monitors workspace state: process tree, listening ports, git/PR info.
/// Owns TTL caches so the 2-second polling loop only spawns subprocesses
/// when data is stale, not on every tick.
public actor WorkspaceMonitor {

    // MARK: - Public types

    public struct PortInfo: Sendable {
        public let port: UInt16
        public let pid: Int32
        public init(port: UInt16, pid: Int32) {
            self.port = port
            self.pid = pid
        }
    }

    public struct GitAndPRResult: Sendable {
        public let branch: String?
        public let isDirty: Bool
        public let ahead: Int
        public let behind: Int
        public let prNumber: Int?
        public let prTitle: String?
        public let prStatus: String?
        public init(branch: String?, isDirty: Bool, ahead: Int, behind: Int,
                    prNumber: Int?, prTitle: String?, prStatus: String?) {
            self.branch = branch
            self.isDirty = isDirty
            self.ahead = ahead
            self.behind = behind
            self.prNumber = prNumber
            self.prTitle = prTitle
            self.prStatus = prStatus
        }
        public static let empty = GitAndPRResult(
            branch: nil, isDirty: false, ahead: 0, behind: 0,
            prNumber: nil, prTitle: nil, prStatus: nil
        )
    }

    // MARK: - TTL constants

    public static let gitInfoTTL: TimeInterval = 20
    public static let sysInfoTTL: TimeInterval = 8

    // MARK: - Private cache state

    private struct GitCacheEntry { let result: GitAndPRResult; let timestamp: Date }
    private struct ProcessTreeCacheEntry { let result: [Int32: Int32]; let timestamp: Date }
    private struct PortCacheEntry { let result: [PortInfo]; let timestamp: Date }

    private var gitInfoCache: [String: GitCacheEntry] = [:]
    private var processTreeCache: ProcessTreeCacheEntry?
    private var portCache: PortCacheEntry?

    public init() {}

    // MARK: - Pure parsing (public for unit tests)

    public static func parseProcessTree(_ output: String) -> [Int32: Int32] {
        var parentMap: [Int32: Int32] = [:]
        for line in output.components(separatedBy: .newlines) {
            let parts = line.split(separator: " ").map(String.init)
            if parts.count >= 2, let pid = Int32(parts[0]), let ppid = Int32(parts[1]) {
                parentMap[pid] = ppid
            }
        }
        return parentMap
    }

    public static func parseListeningPorts(_ output: String) -> [PortInfo] {
        var results: [PortInfo] = []
        var currentPID: Int32?
        var currentAddress: String?
        
        for line in output.components(separatedBy: .newlines) {
            guard !line.isEmpty else { continue }
            
            let prefix = line.first
            let value = String(line.dropFirst())
            
            switch prefix {
            case "p":
                currentPID = Int32(value)
            case "n":
                currentAddress = value
                if let pid = currentPID,
                   let addr = currentAddress,
                   let lastColon = addr.lastIndex(of: ":") {
                    let portStr = String(addr[addr.index(after: lastColon)...])
                    if let port = UInt16(portStr) {
                        results.append(PortInfo(port: port, pid: pid))
                    }
                }
                currentPID = nil
                currentAddress = nil
            default:
                break
            }
        }
        
        return results
    }

    // MARK: - Pure PID ancestry walk

    public static func isDescendant(pid: Int32, parentPID: Int32, parentMap: [Int32: Int32]) -> Bool {
        var current = pid
        var visited = Set<Int32>()
        while current > 0 && !visited.contains(current) {
            if current == parentPID { return true }
            visited.insert(current)
            guard let parent = parentMap[current] else { break }
            current = parent
        }
        return false
    }

    // MARK: - Cached data fetchers

    public func cachedProcessTree() async -> [Int32: Int32] {
        if let c = processTreeCache, Date().timeIntervalSince(c.timestamp) < Self.sysInfoTTL {
            return c.result
        }
        let output = await ProcessRunner.runReturningStdout(
            executable: "/bin/ps", arguments: ["-ax", "-o", "pid=,ppid="], timeout: 10
        ) ?? ""
        let result = Self.parseProcessTree(output)
        processTreeCache = ProcessTreeCacheEntry(result: result, timestamp: Date())
        return result
    }

    public func cachedListeningPorts() async -> [PortInfo] {
        if let c = portCache, Date().timeIntervalSince(c.timestamp) < Self.sysInfoTTL {
            return c.result
        }
        let output = await ProcessRunner.runReturningStdout(
            executable: "/usr/sbin/lsof",
            arguments: ["-iTCP", "-sTCP:LISTEN", "-P", "-n"],
            timeout: 10
        ) ?? ""
        let result = Self.parseListeningPorts(output)
        portCache = PortCacheEntry(result: result, timestamp: Date())
        return result
    }

    public func cachedGitAndPRInfo(for cwd: URL) async -> GitAndPRResult {
        let key = cwd.path
        if let entry = gitInfoCache[key],
           Date().timeIntervalSince(entry.timestamp) < Self.gitInfoTTL {
            return entry.result
        }
        let result = await fetchGitAndPRInfo(for: cwd)
        gitInfoCache[key] = GitCacheEntry(result: result, timestamp: Date())
        return result
    }

    // MARK: - Private git/PR fetch

    private func fetchGitAndPRInfo(for cwd: URL) async -> GitAndPRResult {
        let git = "/usr/bin/git"
        guard let branchOutput = await ProcessRunner.runReturningStdout(
            executable: git, arguments: ["rev-parse", "--abbrev-ref", "HEAD"],
            directory: cwd, timeout: 10
        ), !branchOutput.contains("fatal: not a git repository") else {
            return .empty
        }
        let branch = branchOutput.trimmingCharacters(in: .whitespacesAndNewlines)

        let dirtyOutput = await ProcessRunner.runReturningStdout(
            executable: git, arguments: ["status", "--porcelain"],
            directory: cwd, timeout: 10
        )
        let isDirty = !(dirtyOutput?.isEmpty ?? true)

        var ahead = 0, behind = 0
        if let abOutput = await ProcessRunner.runReturningStdout(
            executable: git,
            arguments: ["rev-list", "--left-right", "--count", "HEAD...@{u}"],
            directory: cwd, timeout: 10
        ) {
            let parts = abOutput.split(separator: "\t").map(String.init)
            if parts.count >= 2, let ah = Int(parts[0]), let be = Int(parts[1]) {
                ahead = ah; behind = be
            }
        }

        var prNumber: Int?
        var prTitle: String?
        var prStatus: String?

        let skipPRLookup = (branch == "main" || branch == "master" || branch == "HEAD")
        if !skipPRLookup {
            let ghPaths = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
            for gp in ghPaths where FileManager.default.fileExists(atPath: gp) {
                guard let json = await ProcessRunner.runReturningStdout(
                    executable: gp,
                    arguments: ["pr", "view", "--json", "number,title,state,reviewDecision"],
                    directory: cwd, timeout: 15
                ),
                let data = json.data(using: .utf8),
                let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { break }

                prNumber = obj["number"] as? Int
                prTitle  = obj["title"]  as? String
                let state    = obj["state"]          as? String ?? ""
                let decision = obj["reviewDecision"] as? String ?? ""
                if state == "MERGED" {
                    prStatus = "merged"
                } else if state == "CLOSED" {
                    prStatus = "closed"
                } else if state == "OPEN" {
                    prStatus = decision == "APPROVED" ? "approved"
                             : decision == "CHANGES_REQUESTED" ? "changes_requested"
                             : "open"
                }
                break
            }
        }

        return GitAndPRResult(
            branch: branch, isDirty: isDirty, ahead: ahead, behind: behind,
            prNumber: prNumber, prTitle: prTitle, prStatus: prStatus
        )
    }
}
