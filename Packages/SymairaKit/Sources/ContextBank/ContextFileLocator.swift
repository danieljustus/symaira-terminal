import Foundation

/// Instruction files the Context Bank panel surfaces for in-place editing.
public enum ContextFileKind: String, CaseIterable, Sendable {
    case claude = "CLAUDE.md"
    case agents = "AGENTS.md"
    case gemini = "GEMINI.md"
    case cursorRules = ".cursorrules"
}

public struct ContextFile: Equatable, Sendable {
    public let kind: ContextFileKind
    public let url: URL
}

/// Finds agent instruction files for a working directory, walking up to the
/// repository root so directory-specific rules and the project root file both
/// appear in the panel (closest first).
public struct ContextFileLocator: Sendable {
    public init() {}

    public func locate(in directory: URL, ascendingTo root: URL? = nil) -> [ContextFile] {
        var results: [ContextFile] = []
        let fm = FileManager.default
        var current = directory.standardizedFileURL
        let stop = root?.standardizedFileURL

        while true {
            for kind in ContextFileKind.allCases {
                let candidate = current.appendingPathComponent(kind.rawValue)
                if fm.fileExists(atPath: candidate.path) {
                    results.append(ContextFile(kind: kind, url: candidate))
                }
            }
            if current == stop || current.pathComponents.count <= 1 { break }
            if stop == nil {
                // Without an explicit root, stop at the nearest git repository root.
                if fm.fileExists(atPath: current.appendingPathComponent(".git").path) { break }
            }
            current.deleteLastPathComponent()
        }
        return results
    }
}
