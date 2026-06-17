import SwiftUI

public struct DiffView: View {
    let diff: String
    let font: Font

    public init(diff: String, font: Font = .system(.caption, design: .monospaced)) {
        self.diff = diff
        self.font = font
    }

    public var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(parseDiff().enumerated()), id: \.offset) { _, line in
                    DiffLine(line: line, font: font)
                }
            }
            .padding(8)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func parseDiff() -> [DiffLineModel] {
        diff.components(separatedBy: .newlines).map { line in
            if line.hasPrefix("+++") || line.hasPrefix("---") {
                return DiffLineModel(text: line, type: .header)
            } else if line.hasPrefix("@@") {
                return DiffLineModel(text: line, type: .hunkHeader)
            } else if line.hasPrefix("+") {
                return DiffLineModel(text: line, type: .addition)
            } else if line.hasPrefix("-") {
                return DiffLineModel(text: line, type: .deletion)
            } else if line.hasPrefix("diff ") || line.hasPrefix("index ")
                || line.hasPrefix("new ") || line.hasPrefix("old ") || line.hasPrefix("@@") {
                return DiffLineModel(text: line, type: .header)
            } else {
                return DiffLineModel(text: line, type: .context)
            }
        }
    }
}

struct DiffLineModel: Identifiable {
    let id = UUID()
    let text: String
    let type: DiffLineType
}

enum DiffLineType {
    case addition
    case deletion
    case context
    case header
    case hunkHeader
}

struct DiffLine: View {
    let line: DiffLineModel
    let font: Font

    var body: some View {
        Text(line.text)
            .font(font)
            .foregroundColor(foregroundColor)
            .background(backgroundColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    private var foregroundColor: Color {
        switch line.type {
        case .addition: return .green
        case .deletion: return .red
        case .context: return .primary
        case .header, .hunkHeader: return .blue
        }
    }

    private var backgroundColor: Color {
        switch line.type {
        case .addition: return Color.green.opacity(0.1)
        case .deletion: return Color.red.opacity(0.1)
        case .context: return .clear
        case .header, .hunkHeader: return Color.blue.opacity(0.05)
        }
    }
}
