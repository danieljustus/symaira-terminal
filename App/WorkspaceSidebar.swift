import SwiftUI
import AgentKit

struct PaneListItem: Identifiable {
    let id: UUID
    let title: String
    let status: AgentStatus
    let isActive: Bool
}

struct WorkspaceSidebar: View {
    let items: [PaneListItem]
    let onSelect: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Panes")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            List(items) { item in
                Button {
                    onSelect(item.id)
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(StatusRingStyle.color(for: item.status))
                            .frame(width: 8, height: 8)
                        Text(item.title)
                            .lineLimit(1)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        if item.isActive {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.accentColor)
                                .font(.caption)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.sidebar)
        }
        .frame(minWidth: 180, idealWidth: 220)
    }
}
