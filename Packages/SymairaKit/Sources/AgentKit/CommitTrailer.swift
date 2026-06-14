import Foundation

public struct CommitTrailer {
    public static let trailerKey = "Symaira-Transcript"

    public static func appendTrailer(to message: String, transcriptID: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let trailer = "\(trailerKey): \(transcriptID)"

        if trimmed.isEmpty {
            return trailer
        }

        return "\(trimmed)\n\n\(trailer)"
    }

    public static func extractTranscriptID(from message: String) -> String? {
        let lines = message.components(separatedBy: .newlines)
        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("\(trailerKey):") {
                let id = String(trimmed.dropFirst("\(trailerKey):".count))
                    .trimmingCharacters(in: .whitespaces)
                if !id.isEmpty {
                    return id
                }
            }
        }
        return nil
    }
}

public actor GitCommitWatcher {
    private let fileManager = FileManager.default
    private var watchedPaths: [String: DispatchSourceFileSystemObject] = [:]

    public init() {}

    public func watch(
        at path: URL,
        onCommit: @escaping @Sendable (String) -> Void
    ) {
        let gitDir = path.appendingPathComponent(".git")
        guard fileManager.fileExists(atPath: gitDir.path) else { return }

        let headsDir = gitDir.appendingPathComponent("refs/heads")
        guard let enumerator = fileManager.enumerator(at: headsDir, includingPropertiesForKeys: nil) else { return }

        while let fileURL = enumerator.nextObject() as? URL {
            let pathString = fileURL.path
            guard watchedPaths[pathString] == nil else { continue }

            let fd = open(pathString, O_EVTONLY)
            guard fd >= 0 else { continue }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write],
                queue: .global()
            )

            source.setEventHandler { [path] in
                onCommit(path.path)
            }

            source.setCancelHandler {
                close(fd)
            }

            watchedPaths[pathString] = source
            source.resume()
        }
    }

    public func stopWatching() {
        for (_, source) in watchedPaths {
            source.cancel()
        }
        watchedPaths.removeAll()
    }
}
