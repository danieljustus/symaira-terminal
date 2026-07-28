import AppKit
import Foundation
import TerminalCore

/// Represents a logical tab in the terminal app. Each tab owns its own set of
/// terminal panes (split panes) and their layout tree. The tab bar shows one
/// entry per tab, not per pane — splitting a pane creates a new pane within
/// the same tab, not a separate tab entry.
@MainActor
final class Tab {
    let tabID = UUID()
    var title: String
    var panes: [TerminalPane] = []
    var currentLayout: SplitNode = .pane(index: 0)
    var currentPaneIndex: Int = 0
    var zoomedPane: TerminalPane?
    var splitViews: [UUID: NSSplitView] = [:]

    /// The currently active pane in this tab, derived from `currentPaneIndex`.
    var currentPane: TerminalPane? {
        guard !panes.isEmpty, currentPaneIndex < panes.count else { return nil }
        return panes[currentPaneIndex]
    }

    init(title: String = "Terminal") {
        self.title = title
    }
}
