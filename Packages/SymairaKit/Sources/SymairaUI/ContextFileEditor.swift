import SwiftUI
import ContextBank

public struct ContextFileEditor: View {
    let file: ContextFile
    @State private var content: String = ""
    @State private var isSaving = false
    @State private var error: String?

    public init(file: ContextFile) {
        self.file = file
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(file.kind.rawValue)
                    .font(.headline)
                Spacer()
                Text(file.url.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding()

            Divider()

            if let error = error {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
            } else {
                TextEditor(text: $content)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.visible)
                    .padding(4)
            }

            Divider()

            HStack {
                Spacer()
                Button("Save") {
                    save()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(isSaving)
            }
            .padding()
        }
        .frame(minWidth: 400, minHeight: 300)
        .onAppear {
            loadContent()
        }
    }

    private func loadContent() {
        do {
            content = try String(contentsOf: file.url, encoding: .utf8)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save() {
        isSaving = true
        error = nil

        do {
            try content.write(to: file.url, atomically: true, encoding: .utf8)
            isSaving = false
        } catch {
            self.error = error.localizedDescription
            isSaving = false
        }
    }
}
