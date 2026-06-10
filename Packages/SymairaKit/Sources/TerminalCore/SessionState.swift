import Foundation

/// Serializable snapshot of one terminal pane's configuration for persistence
/// across app restarts. Does NOT include scrollback content (privacy + cost).
public struct PaneState: Codable, Equatable, Sendable {
    /// Shell executable (e.g. "/bin/zsh").
    public var executablePath: String
    /// Arguments passed to the shell (e.g. ["-l"]).
    public var arguments: [String]
    /// Working directory at the time of save.
    public var workingDirectory: String?
    /// Sanitized environment snapshot (secrets stripped).
    public var environment: [String: String]
    /// Initial terminal dimensions.
    public var columns: UInt16
    public var rows: UInt16

    public init(
        executablePath: String = "/bin/zsh",
        arguments: [String] = ["-l"],
        workingDirectory: String? = nil,
        environment: [String: String] = [:],
        columns: UInt16 = 80,
        rows: UInt16 = 24
    ) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.columns = columns
        self.rows = rows
    }
}

/// Geometry of a split layout. Encodes a binary tree of horizontal/vertical
/// splits, each leaf holding a pane index.
public indirect enum SplitNode: Codable, Equatable, Sendable {
    case pane(index: Int)
    case split(orientation: SplitOrientation, ratio: Double, left: SplitNode, right: SplitNode)
}

public enum SplitOrientation: String, Codable, Sendable {
    case horizontal
    case vertical
}

/// Complete window state for persistence. Captures pane configurations and the
/// split geometry so the layout can be reconstructed on relaunch.
public struct SessionState: Codable, Equatable, Sendable {
    public var panes: [PaneState]
    public var layout: SplitNode
    /// Window frame in screen coordinates (saved for position restoration).
    public var windowFrame: CodableRect

    public init(
        panes: [PaneState] = [PaneState()],
        layout: SplitNode = .pane(index: 0),
        windowFrame: CodableRect = CodableRect(x: 0, y: 0, width: 960, height: 600)
    ) {
        self.panes = panes
        self.layout = layout
        self.windowFrame = windowFrame
    }
}

/// Codable wrapper around NSRect/CGRect for persistence.
public struct CodableRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    #if canImport(AppKit)
    public init(_ rect: NSRect) {
        self.x = rect.origin.x
        self.y = rect.origin.y
        self.width = rect.size.width
        self.height = rect.size.height
    }

    public var nsRect: NSRect {
        NSRect(x: x, y: y, width: width, height: height)
    }
    #endif
}
