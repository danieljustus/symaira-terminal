import SwiftUI
import UsageKit

/// Full usage detail panel — per-provider progress bars, badges, quota overlays,
/// and a time-bucket toggle (Today / This Week / This Month).
public struct UsageDetailView: View {
    @ObservedObject var store: UsageStore
    @Environment(\.dismiss) private var dismiss

    public init(store: UsageStore) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: Header
            HStack {
                Text("AI Usage")
                    .font(.headline)
                Spacer()
                if store.isRefreshing {
                    ProgressView().scaleEffect(0.6)
                } else {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh usage data")
                }
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // MARK: Bucket Picker
            Picker("Period", selection: $store.selectedBucket) {
                ForEach(TimeBucket.allCases, id: \.self) { bucket in
                    Text(bucket.rawValue).tag(bucket)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            // MARK: Totals Summary
            let totals = store.totalsForSelectedBucket
            TotalsBadge(totals: totals)
                .padding(.horizontal)

            Divider().padding(.vertical, 4)

            // MARK: Billing Window (Claude)
            let window = store.currentBillingWindow
            if window.totals.sampleCount > 0 || window.isActive {
                BillingWindowRow(window: window)
                    .padding(.horizontal)
                Divider().padding(.vertical, 4)
            }

            // MARK: Per-Provider Rows
            if store.byProviderTotals.isEmpty {
                EmptyUsageView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(sortedProviders, id: \.provider.id) { entry in
                            ProviderUsageRow(
                                provider: entry.provider,
                                totals: entry.totals,
                                quota: store.quotaResult.quotas.filter { $0.provider == entry.provider }
                            )
                        }
                    }
                    .padding()
                }
            }

            // MARK: Last Refresh
            if let date = store.lastRefreshDate {
                Divider()
                Text("Updated \(date, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(6)
            }
        }
    }

    private var sortedProviders: [(provider: UsageProvider, totals: UsageTotals)] {
        store.byProviderTotals
            .map { ($0.key, $0.value) }
            .sorted { $0.totals.totalTokens > $1.totals.totalTokens }
    }
}

// MARK: - Sub-views

private struct TotalsBadge: View {
    let totals: UsageTotals

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tokens").font(.caption2).foregroundStyle(.secondary)
                Text(formatTokens(totals.totalTokens)).font(.title3.monospacedDigit().bold())
            }
            if let cost = totals.costUSD {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cost").font(.caption2).foregroundStyle(.secondary)
                    Text("$\(formatCost(cost))").font(.title3.monospacedDigit().bold())
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Sessions").font(.caption2).foregroundStyle(.secondary)
                Text("\(totals.sampleCount)").font(.title3.monospacedDigit().bold())
            }
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func formatTokens(_ n: Int) -> String {
        n >= 1_000_000 ? "\(String(format: "%.2f", Double(n) / 1_000_000))M"
        : n >= 1_000   ? "\(String(format: "%.1f", Double(n) / 1_000))k"
        : "\(n)"
    }

    private func formatCost(_ d: Decimal) -> String {
        let n = NSDecimalNumber(decimal: d)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 4
        return f.string(from: n) ?? d.description
    }
}

private struct BillingWindowRow: View {
    let window: BillingWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("5-hour billing window", systemImage: "clock")
                    .font(.caption.bold())
                Spacer()
                if window.isActive {
                    Text("resets in \(window.end, style: .relative)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("\(window.totals.totalTokens) tokens this window")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct ProviderUsageRow: View {
    let provider: UsageProvider
    let totals: UsageTotals
    let quota: [UsageQuota]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(provider.displayName).font(.subheadline.bold())
                Spacer()
                if let cost = totals.costUSD {
                    Text("$\(formatCost(cost))")
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.blue.opacity(0.15), in: Capsule())
                }
            }

            // Quota progress bars
            ForEach(quota, id: \.label) { q in
                QuotaProgressRow(quota: q)
            }

            // Token breakdown
            HStack(spacing: 12) {
                TokenBadge(label: "In", value: totals.inputTokens)
                TokenBadge(label: "Out", value: totals.outputTokens)
                if totals.cacheCreationTokens > 0 {
                    TokenBadge(label: "Cache↑", value: totals.cacheCreationTokens)
                }
                if totals.cacheReadTokens > 0 {
                    TokenBadge(label: "Cache↓", value: totals.cacheReadTokens)
                }
            }
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func formatCost(_ d: Decimal) -> String {
        let n = NSDecimalNumber(decimal: d)
        let f = NumberFormatter()
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 4
        return f.string(from: n) ?? d.description
    }
}

private struct QuotaProgressRow: View {
    let quota: UsageQuota

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(quota.label).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if let limit = quota.limit {
                    Text("\(quota.used) / \(limit) \(quota.unit.rawValue)")
                        .font(.caption2.monospacedDigit())
                } else {
                    Text("\(quota.used) \(quota.unit.rawValue)")
                        .font(.caption2.monospacedDigit())
                }
            }
            if let fraction = quota.fractionUsed {
                ProgressView(value: fraction)
                    .tint(fraction > 0.9 ? .red : fraction > 0.7 ? .orange : .blue)
            }
            if let resetsAt = quota.resetsAt {
                Text("Resets \(resetsAt, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct TokenBadge: View {
    let label: String
    let value: Int

    var body: some View {
        VStack(spacing: 0) {
            Text(label).font(.caption2).foregroundStyle(.tertiary)
            Text(formatTokens(value)).font(.caption2.monospacedDigit())
        }
    }

    private func formatTokens(_ n: Int) -> String {
        n >= 1_000_000 ? "\(String(format: "%.1f", Double(n) / 1_000_000))M"
        : n >= 1_000   ? "\(String(format: "%.0f", Double(n) / 1_000))k"
        : "\(n)"
    }
}

private struct EmptyUsageView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No usage data yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Run Claude Code, Codex, or other agents to\nsee token usage and cost here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }
}
