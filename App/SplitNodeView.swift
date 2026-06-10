import AppKit
import TerminalCore

@MainActor
protocol SplitNodeDelegate: AnyObject {
    func splitNode(_ node: SplitNodeView, didSelect pane: TerminalPane)
    func splitNodeDidRequestSplit(_ node: SplitNodeView, orientation: SplitOrientation)
}

@MainActor
indirect enum SplitNodeView {
    case pane(TerminalPane)
    case split(orientation: SplitOrientation, ratio: Double, left: SplitNodeView, right: SplitNodeView)

    var leafPanes: [TerminalPane] {
        switch self {
        case .pane(let pane): [pane]
        case .split(_, _, let left, let right): left.leafPanes + right.leafPanes
        }
    }

    var depth: Int {
        switch self {
        case .pane: 0
        case .split(_, _, let left, let right): 1 + max(left.depth, right.depth)
        }
    }

    func replacePane(_ old: TerminalPane, with new: TerminalPane) -> SplitNodeView {
        switch self {
        case .pane(let p) where p === old:
            .pane(new)
        case .pane:
            self
        case .split(let o, let r, let l, let rr):
            .split(orientation: o, ratio: r, left: l.replacePane(old, with: new), right: rr.replacePane(old, with: new))
        }
    }

    func removePane(_ target: TerminalPane) -> SplitNodeView? {
        switch self {
        case .pane(let p) where p === target:
            nil
        case .pane:
            self
        case .split(_, _, let left, let right):
            let newLeft = left.removePane(target)
            let newRight = right.removePane(target)
            switch (newLeft, newRight) {
            case (.some(let l), .some(let r)):
                .split(orientation: .horizontal, ratio: 0.5, left: l, right: r)
            case (.some(let l), .none):
                l
            case (.none, .some(let r)):
                r
            case (.none, .none):
                nil
            }
        }
    }
}
