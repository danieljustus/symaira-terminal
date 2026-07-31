import AppKit
import SwiftUI
import TerminalCore
import SymairaTheme

@MainActor
public final class CommandInputEditor: NSObject, ObservableObject {
    public enum Mode: Sendable {
        case shell
        case prompt
    }

    @Published public var mode: Mode = .shell
    @Published public var isVisible: Bool = true
    @Published public var text: String = ""
    @Published public var cursorPosition: Int = 0
    @Published public var isSTTAuthorized: Bool = false
    @Published public var sttError: String?

    public let sttService = STTService()

    private var history: [String] = []
    private var historyIndex: Int = -1
    private let textView: NSTextView
    private let scrollView: NSScrollView
    private weak var surface: (any TerminalSurface)?
    private var isAlternateScreenActive: Bool = false
    private var lastRecognizedText: String = ""

    public init(surface: (any TerminalSurface)?) {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        layoutManager.addTextContainer(textContainer)

        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textColor = NSColor.labelColor
        textView.insertionPointColor = NSColor.controlAccentColor
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.3)
        ]

        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(width: textView.frame.size.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = 0

        self.textView = textView

        let scrollView = NSScrollView(frame: .zero)
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        self.scrollView = scrollView

        super.init()

        self.surface = surface
        textView.delegate = self
        sttService.delegate = self
        setupKeyBindings()
        updatePlaceholder()
    }

    public var view: NSView {
        scrollView
    }

    public func toggleMode() {
        mode = mode == .shell ? .prompt : .shell
        updatePlaceholder()
    }

    public func clear() {
        textView.string = ""
        text = ""
        cursorPosition = 0
        historyIndex = -1
    }

    public func requestSTTAuthorization() {
        sttService.requestAuthorization { [weak self] authorized in
            guard let self else { return }
            self.isSTTAuthorized = authorized
            if authorized {
                self.startSTTRecording()
            } else {
                self.sttError = "Speech recognition not authorized. Enable it in System Settings → Privacy & Security."
            }
        }
    }

    public func toggleSTTRecording() {
        if sttService.isRecording {
            sttService.stopRecording()
            return
        }

        if !isSTTAuthorized {
            requestSTTAuthorization()
            return
        }

        startSTTRecording()
    }

    private func startSTTRecording() {
        sttError = nil
        lastRecognizedText = ""
        do {
            try sttService.startRecording()
        } catch {
            sttError = error.localizedDescription
            NSLog("symaira stt: failed to start recording — \(error.localizedDescription)")
        }
    }

    private func insertRecognizedText(_ newText: String) {
        let delta: String
        if newText.hasPrefix(lastRecognizedText) {
            delta = String(newText.dropFirst(lastRecognizedText.count))
        } else {
            delta = newText
        }
        lastRecognizedText = newText

        guard !delta.isEmpty else { return }

        let cursor = textView.selectedRange.location
        let nsRange = NSRange(location: cursor, length: 0)
        textView.insertText(delta, replacementRange: nsRange)
    }

    public func setAlternateScreenActive(_ active: Bool) {
        isAlternateScreenActive = active
        isVisible = !active
    }

    private func setupKeyBindings() {
    }

    private func updatePlaceholder() {
        // NSTextView does not expose placeholderString as a public property.
        // Placeholder is handled visually via the CommandInputBar overlay.
    }

    private func submitInput() {
        let input = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        if let last = history.last, last == input {
        } else {
            history.append(input)
        }
        historyIndex = -1

        let textToSend = mode == .shell ? input : input + "\n"
        surface?.sendText(textToSend)

        clear()
    }

    private func navigateHistory(direction: Int) {
        guard !history.isEmpty else { return }

        let newIndex = historyIndex + direction
        guard newIndex >= -1, newIndex < history.count else { return }

        historyIndex = newIndex

        if newIndex == -1 {
            textView.string = ""
            text = ""
        } else {
            let entry = history[history.count - 1 - newIndex]
            textView.string = entry
            text = entry
            let endRange = NSRange(location: entry.utf16.count, length: 0)
            textView.selectedRange = endRange
        }
    }
}

extension CommandInputEditor: NSTextViewDelegate {
    public func textDidChange(_ notification: Notification) {
        text = textView.string
        cursorPosition = textView.selectedRange.location
    }

    public func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            submitInput()
            return true

        case #selector(NSResponder.moveUp(_:)):
            navigateHistory(direction: 1)
            return true

        case #selector(NSResponder.moveDown(_:)):
            navigateHistory(direction: -1)
            return true

        case #selector(NSResponder.insertTab(_:)):
            return false

        default:
            return false
        }
    }
}

public struct CommandInputEditorView: NSViewRepresentable {
    @ObservedObject var editor: CommandInputEditor

    public init(editor: CommandInputEditor) {
        self.editor = editor
    }

    public func makeNSView(context: Context) -> NSView {
        editor.view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        nsView.isHidden = !editor.isVisible
    }
}

public struct CommandInputBar: View {
    @ObservedObject var editor: CommandInputEditor

    public init(editor: CommandInputEditor) {
        self.editor = editor
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let error = editor.sttError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text(error)
                        .font(.system(size: 11))
                        .lineLimit(2)
                    Spacer()
                    Button {
                        editor.sttError = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.yellow.opacity(0.15))
                .foregroundColor(.secondary)
            }

            CommandInputEditorView(editor: editor)
                .frame(minHeight: 28, idealHeight: 36)

            HStack(spacing: 8) {
                // Mode indicator
                HStack(spacing: 4) {
                    Image(systemName: editor.mode == .shell ? "terminal" : "bubble.left.and.bubble.right")
                        .font(.system(size: 9, weight: .medium))
                    Text(editor.mode == .shell ? "Shell" : "Prompt")
                        .font(.system(size: 10, weight: .medium))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(editor.mode == .shell ? 0.12 : 0.18))
                .cornerRadius(4)
                .help(editor.mode == .shell ? "Shell mode — type a command and press ⏎" : "Prompt mode — type a message and press ⏎")
                .onTapGesture {
                    editor.toggleMode()
                }

                Spacer()

                if editor.sttService.isRecording {
                    Text("Recording…")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                }

                Button {
                    editor.toggleSTTRecording()
                } label: {
                    Image(systemName: editor.sttService.isRecording ? "mic.fill" : "mic")
                        .font(.system(size: 12))
                        .foregroundColor(editor.sttService.isRecording ? .red : .secondary)
                }
                .buttonStyle(.plain)
                .help(editor.sttService.isRecording ? "Stop dictation" : "Start dictation")
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        }
    }
}

extension CommandInputEditor: STTServiceDelegate {
    public func sttService(_ service: STTService, didRecognize text: String) {
        insertRecognizedText(text)
    }

    public func sttService(_ service: STTService, didFailWithError error: Error) {
        sttError = error.localizedDescription
        NSLog("symaira stt: recognition error — \(error.localizedDescription)")
    }

    public func sttServiceDidFinishRecording(_ service: STTService) {
        lastRecognizedText = ""
    }
}

#if DEBUG
struct CommandInputEditorPreview: View {
    @StateObject private var editor = CommandInputEditor(surface: nil)

    var body: some View {
        VStack {
            Text("Mode: \(editor.mode == .shell ? "Shell" : "Prompt")")
                .font(SymairaTypography.subheading)
            CommandInputEditorView(editor: editor)
                .frame(height: 100)
                .border(Color.gray.opacity(0.3))
            HStack {
                Button("Toggle Mode") { editor.toggleMode() }
                Button("Clear") { editor.clear() }
            }
        }
        .padding()
    }
}
#endif
