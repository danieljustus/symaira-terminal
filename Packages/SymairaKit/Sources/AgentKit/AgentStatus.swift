import Foundation

/// Lifecycle state of an agent session, driving pane rings and the sidebar.
public enum AgentStatus: String, Codable, Equatable, Sendable, CaseIterable {
    case idle
    case running
    case awaitingApproval
    case error
    case done
}

/// Where a status observation came from. Higher trust wins on conflict:
/// structured ACP events beat OSC notifications beat output heuristics.
public enum StatusSource: Int, Codable, Comparable, Sendable {
    case heuristic = 0
    case osc = 1
    case acp = 2

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct StatusObservation: Equatable, Sendable {
    public var status: AgentStatus
    public var source: StatusSource
    public var detail: String?

    public init(_ status: AgentStatus, source: StatusSource, detail: String? = nil) {
        self.status = status
        self.source = source
        self.detail = detail
    }
}

/// Pure reducer combining observations from multiple sources into one status.
///
/// Rules:
/// - An observation from a source with priority >= the current one always applies.
/// - A lower-priority source may only override a *settled* state (`idle`/`done`),
///   never an active one (`running`/`awaitingApproval`/`error`) claimed by a more
///   trusted source — heuristics must not clear an ACP-reported approval prompt.
/// - Process exit (`processExited`) always settles the session regardless of source.
public struct AgentStatusEngine: Sendable {
    public private(set) var current: AgentStatus = .idle
    public private(set) var currentSource: StatusSource = .heuristic
    public private(set) var detail: String?

    public init() {}

    @discardableResult
    public mutating func apply(_ observation: StatusObservation) -> AgentStatus {
        let settled = current == .idle || current == .done
        guard observation.source >= currentSource || settled else { return current }
        current = observation.status
        currentSource = observation.source
        detail = observation.detail
        return current
    }

    /// The underlying process terminated: settle to `done` (exit 0) or `error`.
    @discardableResult
    public mutating func processExited(code: Int32) -> AgentStatus {
        current = code == 0 ? .done : .error
        currentSource = .acp // terminal fact, nothing may downgrade it silently
        detail = code == 0 ? nil : "exit \(code)"
        return current
    }
}
