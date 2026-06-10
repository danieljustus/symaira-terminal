import AgentKit
import SwiftUI

/// Visual mapping of agent status to the pane ring (and sidebar dots).
public enum StatusRingStyle {
    public static func color(for status: AgentStatus) -> Color {
        switch status {
        case .idle: .clear
        case .running: .green
        case .awaitingApproval: .blue
        case .error: .red
        case .done: .secondary
        }
    }

    /// Approval and error states pulse to draw the eye; activity stays calm.
    public static func pulses(_ status: AgentStatus) -> Bool {
        status == .awaitingApproval || status == .error
    }
}

/// Animated ring drawn around a terminal pane reflecting its agent status.
public struct StatusRing: ViewModifier {
    let status: AgentStatus
    @State private var pulsing = false

    public init(status: AgentStatus) {
        self.status = status
    }

    public func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(StatusRingStyle.color(for: status), lineWidth: 2)
                    .opacity(StatusRingStyle.pulses(status) ? (pulsing ? 1.0 : 0.35) : 0.9)
                    .animation(
                        StatusRingStyle.pulses(status)
                            ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                            : .default,
                        value: pulsing
                    )
            }
            .onAppear { pulsing = true }
    }
}

extension View {
    public func agentStatusRing(_ status: AgentStatus) -> some View {
        modifier(StatusRing(status: status))
    }
}
