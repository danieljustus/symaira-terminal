import AgentKit
import AppKit
import SwiftUI
import Testing
@testable import SymairaUI

// MARK: - StatusRingStyle

/// Pure mapping of agent status → ring visuals. No rendering involved:
/// color semantics are verified through the resolved RGBA components.
@Suite struct StatusRingStyleTests {
    @Test func pulsesOnlyForApprovalAndError() {
        #expect(StatusRingStyle.pulses(.awaitingApproval))
        #expect(StatusRingStyle.pulses(.error))
        #expect(!StatusRingStyle.pulses(.idle))
        #expect(!StatusRingStyle.pulses(.running))
        #expect(!StatusRingStyle.pulses(.done))
    }

    @Test func idleStatusIsInvisible() {
        // `.idle` maps to `.clear` so the ring disappears entirely.
        #expect(resolvedAlpha(of: StatusRingStyle.color(for: .idle)) == 0)
    }

    @Test func activeStatusesAreOpaque() {
        // Error/approval/running draw a fully opaque ring; `.done` maps to
        // `.secondary`, which macOS renders with partial opacity.
        for status in [AgentStatus.running, .awaitingApproval, .error] {
            #expect(resolvedAlpha(of: StatusRingStyle.color(for: status)) == 1,
                    "expected opaque ring for \(status)")
        }
        let doneAlpha = resolvedAlpha(of: StatusRingStyle.color(for: .done))
        #expect(doneAlpha > 0 && doneAlpha < 1,
                "expected muted ring for .done, got alpha \(doneAlpha)")
    }

    @Test func errorAndApprovalUseDistinctHues() {
        // Red for failure, blue for waiting — distinct hues that must not
        // collapse onto the same color.
        let errorRGB = resolvedRGB(of: StatusRingStyle.color(for: .error))
        let approvalRGB = resolvedRGB(of: StatusRingStyle.color(for: .awaitingApproval))
        #expect(errorRGB != approvalRGB)
        // Red hue: red channel dominates.
        #expect(errorRGB.r > errorRGB.g && errorRGB.r > errorRGB.b)
        // Blue hue: blue channel dominates.
        #expect(approvalRGB.b > approvalRGB.r && approvalRGB.b > approvalRGB.g)
    }

    // MARK: - Helpers

    private func resolvedRGBA(of color: Color) -> (r: Double, g: Double, b: Double, a: Double) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        return (
            (ns.redComponent * 1000).rounded() / 1000,
            (ns.greenComponent * 1000).rounded() / 1000,
            (ns.blueComponent * 1000).rounded() / 1000,
            (ns.alphaComponent * 1000).rounded() / 1000
        )
    }

    private func resolvedAlpha(of color: Color) -> Double {
        resolvedRGBA(of: color).a
    }

    private func resolvedRGB(of color: Color) -> (r: Double, g: Double, b: Double) {
        let rgba = resolvedRGBA(of: color)
        return (rgba.r, rgba.g, rgba.b)
    }
}
