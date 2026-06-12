import Foundation

public enum TaskIDError: Error, Equatable, LocalizedError {
    case empty
    case tooLong(maxLength: Int)
    case invalidCharacter(Character)
    case pathSeparator
    case dotSegment
    case invalidBranchName

    public var errorDescription: String? {
        switch self {
        case .empty:
            return "Task ID cannot be empty"
        case .tooLong(let max):
            return "Task ID exceeds maximum length of \(max) characters"
        case .invalidCharacter(let c):
            return "Task ID contains invalid character: '\(c)'"
        case .pathSeparator:
            return "Task ID cannot contain path separators"
        case .dotSegment:
            return "Task ID cannot contain dot segments (.. or .)"
        case .invalidBranchName:
            return "Task ID would create an invalid git branch name"
        }
    }
}

public struct TaskIDValidator: Sendable {
    public static let maxLength = 100
    private static let allowedPattern = "^[A-Za-z0-9._-]+$"

    public init() {}

    public func validate(_ taskID: String) throws {
        guard !taskID.isEmpty else { throw TaskIDError.empty }
        guard taskID.count <= Self.maxLength else { throw TaskIDError.tooLong(maxLength: Self.maxLength) }

        for char in taskID {
            if char == "/" || char == "\\" {
                throw TaskIDError.pathSeparator
            }
        }

        if taskID.contains("..") || taskID == "." || taskID.hasPrefix("./") || taskID.hasSuffix("/.") {
            throw TaskIDError.dotSegment
        }

        guard taskID.range(of: Self.allowedPattern, options: .regularExpression) != nil else {
            if let invalidChar = taskID.first(where: { c in
                let isASCII = c.isASCII
                let isASCIILetter = (c >= "a" && c <= "z") || (c >= "A" && c <= "Z")
                let isASCIINumber = c >= "0" && c <= "9"
                let isAllowedSpecial = c == "." || c == "_" || c == "-"
                return !(isASCIILetter || isASCIINumber || isAllowedSpecial)
            }) {
                throw TaskIDError.invalidCharacter(invalidChar)
            }
            throw TaskIDError.invalidBranchName
        }

        if taskID.hasPrefix(".") || taskID.hasPrefix("-") {
            throw TaskIDError.invalidBranchName
        }

        if taskID.contains("//") || taskID.hasSuffix("/") {
            throw TaskIDError.pathSeparator
        }
    }

    public func sanitizedPath(for taskID: String, under container: URL) throws -> URL {
        try validate(taskID)
        let path = container.appendingPathComponent(taskID, isDirectory: true)
        let canonicalPath = path.standardizedFileURL
        let canonicalContainer = container.standardizedFileURL

        guard canonicalPath.path.hasPrefix(canonicalContainer.path) else {
            throw TaskIDError.pathSeparator
        }

        return canonicalPath
    }
}
