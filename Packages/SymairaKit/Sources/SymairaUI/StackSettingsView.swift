import StackKit
import SwiftUI

/// Settings view for the Symaira Stack — shows detected tools and MCP preset export.
public struct StackSettingsView: View {
    @ObservedObject var store: StackStore
    @State private var showingExportSheet = false
    @State private var showingClaudeCodeSheet = false
    @State private var exportURL: URL?

    public init(store: StackStore) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            toolList
            Divider()
            actionButtons
        }
        .frame(minWidth: 450, minHeight: 350)
        .task {
            if store.detectedTools.isEmpty {
                await store.scan()
            }
        }
        .fileExporter(
            isPresented: $showingExportSheet,
            document: MCPPresetDocument(preset: store.preset),
            contentType: .json,
            defaultFilename: "symaira-mcp"
        ) { result in
            switch result {
            case .success(let url):
                try? store.exportPreset(to: url)
            case .failure(let error):
                store.error = error.localizedDescription
            }
        }
        .sheet(isPresented: $showingClaudeCodeSheet) {
            ClaudeCodeCommandsSheet(commands: store.claudeCodeCommands)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Symaira Stack")
                    .font(.headline)
                Text("\(store.installedCount) of \(store.totalCount) tools detected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                Task { await store.scan() }
            } label: {
                if store.isScanning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(store.isScanning)
        }
        .padding()
    }

    // MARK: - Tool List

    private var toolList: some View {
        List {
            ForEach(store.detectedTools) { tool in
                ToolRow(tool: tool, store: store)
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                showingExportSheet = true
            } label: {
                Label("Export MCP Preset", systemImage: "square.and.arrow.up")
            }
            .disabled(store.installedCount == 0)

            Button {
                showingClaudeCodeSheet = true
            } label: {
                Label("Claude Code Commands", systemImage: "terminal")
            }
            .disabled(store.claudeCodeCommands.isEmpty)

            Spacer()

            if let error = store.error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
        }
        .padding()
    }
}

// MARK: - Tool Row

struct ToolRow: View {
    let tool: DetectedTool
    @ObservedObject var store: StackStore
    @State private var showingInstallConfirm = false
    @State private var selectedClient: MCPClient?

    var body: some View {
        HStack {
            Image(systemName: tool.isInstalled ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundColor(tool.isInstalled ? .green : .red)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(tool.displayName)
                    .font(.body)
                if let version = tool.version {
                    Text(version)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if !tool.isInstalled {
                    Text("Not installed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if !tool.isInstalled {
                installHint
            }
        }
        .contextMenu {
            if tool.isInstalled {
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(tool.path ?? "", forType: .string)
                }
                Button("Copy Install Command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        "brew install \(tool.homebrewFormula)",
                        forType: .string
                    )
                }
            } else {
                Button("Copy Install Command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        "brew install \(tool.homebrewFormula)",
                        forType: .string
                    )
                }
            }
        }
    }

    private var installHint: some View {
        HStack(spacing: 4) {
            Text("brew install")
                .font(.caption2)
                .foregroundColor(.secondary)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    "brew install \(tool.homebrewFormula)",
                    forType: .string
                )
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .help("Copy install command")
        }
    }
}

// MARK: - Claude Code Commands Sheet

struct ClaudeCodeCommandsSheet: View {
    let commands: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Claude Code MCP Setup")
                .font(.headline)

            Text("Run these commands in your terminal to add Symaira MCP servers to Claude Code:")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(commands, id: \.self) { command in
                        HStack {
                            Text(command)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                            Spacer()
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(command, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.clipboard")
                            }
                            .buttonStyle(.plain)
                            .help("Copy command")
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
            }

            Button("Done") {
                dismiss()
            }
        }
        .padding(20)
        .frame(width: 550, height: 300)
    }
}

// MARK: - Document for File Export

import UniformTypeIdentifiers

struct MCPPresetDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let preset: MCPPresetGenerator.MCPPreset

    init(preset: MCPPresetGenerator.MCPPreset) {
        self.preset = preset
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.preset = try MCPPresetGenerator.decode(from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try MCPPresetGenerator.encode(preset)
        return FileWrapper(regularFileWithContents: data)
    }
}
