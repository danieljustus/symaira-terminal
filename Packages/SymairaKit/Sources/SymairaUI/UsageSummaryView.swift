import SwiftUI
import UsageKit

/// Compact toolbar/status-bar element showing today's cost or token total.
///
/// Designed to sit in the window toolbar alongside the tab bar. Clicking opens
/// the `UsageDetailView` sheet.
public struct UsageSummaryView: View {
    @ObservedObject var store: UsageStore
    @State private var showDetail = false

    public init(store: UsageStore) {
        self.store = store
    }

    public var body: some View {
        Button {
            showDetail.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chart.bar.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(summaryText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(store.isRefreshing ? .secondary : .primary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help("AI usage today — click for details")
        .sheet(isPresented: $showDetail) {
            UsageDetailView(store: store)
                .frame(minWidth: 420, minHeight: 480)
        }
    }

    private var summaryText: String {
        let totals = store.totalsForSelectedBucket
        if let cost = totals.costUSD {
            return "$\(formatCost(cost))"
        } else if totals.sampleCount > 0 {
            return "\(formatTokens(totals.totalTokens)) tok"
        } else {
            return "No usage"
        }
    }

    private func formatCost(_ d: Decimal) -> String {
        let n = NSDecimalNumber(decimal: d)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 4
        return f.string(from: n) ?? d.description
    }

    private func formatTokens(_ n: Int) -> String {
        n >= 1_000_000 ? "\(String(format: "%.1f", Double(n) / 1_000_000))M"
        : n >= 1_000   ? "\(String(format: "%.1f", Double(n) / 1_000))k"
        : "\(n)"
    }
}
