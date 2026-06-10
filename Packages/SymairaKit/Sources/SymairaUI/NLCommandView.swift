import SwiftUI

public struct NLCommandView: View {
    let description: String
    let command: String?
    let isLoading: Bool
    let error: String?
    let onAccept: (String) -> Void
    let onReject: () -> Void

    @State private var isHovering = false

    public init(
        description: String,
        command: String? = nil,
        isLoading: Bool = false,
        error: String? = nil,
        onAccept: @escaping (String) -> Void,
        onReject: @escaping () -> Void
    ) {
        self.description = description
        self.command = command
        self.isLoading = isLoading
        self.error = error
        self.onAccept = onAccept
        self.onReject = onReject
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkle")
                    .foregroundColor(.accentColor)
                Text("NL → Command")
                    .font(.headline)
                Spacer()
                Button(action: onReject) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text("\"\(description)\"")
                .font(.caption)
                .foregroundColor(.secondary)

            if isLoading {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Generating command...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if let error = error {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            } else if let command = command {
                Text("Suggested command:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(command)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(4)

                HStack {
                    Spacer()
                    Button("Reject") {
                        onReject()
                    }
                    Button("Accept") {
                        onAccept(command)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(12)
        .frame(width: 400)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .shadow(radius: 4)
    }
}
