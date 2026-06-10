import SwiftUI

struct CommandPaletteItem: Identifiable {
    let id = UUID()
    let name: String
    let shortcut: String?
    let category: String
    let action: () -> Void
}

struct CommandPalette: View {
    @Binding var isPresented: Bool
    let items: [CommandPaletteItem]
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    private var filteredItems: [CommandPaletteItem] {
        if searchText.isEmpty { return items }
        let query = searchText.lowercased()
        return items.filter {
            $0.name.lowercased().contains(query) ||
            $0.category.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Type a command...", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredItems) { item in
                        Button {
                            item.action()
                            isPresented = false
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.system(.body, design: .default))
                                    Text(item.category)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if let shortcut = item.shortcut {
                                    Text(shortcut)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(width: 400, height: 320)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        .onAppear {
            isSearchFocused = true
        }
    }
}
