import SwiftUI
import SymairaUpdateCheck

/// A subtle notification banner shown when a newer release is available.
struct UpdateBannerView: View {
    @ObservedObject var controller: AppUpdateCheckController

    var body: some View {
        switch controller.status {
        case .available(let release):
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle")
                    .foregroundColor(.accentColor)
                Text("\(release.tagName) available")
                    .font(.caption)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button("View") { controller.openReleasePage() }
                    .buttonStyle(.link)
                    .controlSize(.small)
                Button("Skip") { controller.skipCurrentVersion() }
                    .buttonStyle(.plain)
                    .controlSize(.small)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(Divider(), alignment: .top)
        case .error:
            EmptyView()
        case .skipped, .unknown, .upToDate:
            EmptyView()
        }
    }
}
