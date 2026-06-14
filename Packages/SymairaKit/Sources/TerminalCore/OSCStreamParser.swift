import Foundation

/// Events extracted from the PTY byte stream that the host app reacts to.
public enum OSCEvent: Equatable, Sendable {
    /// OSC 0 / OSC 2 — window/tab title set by the shell or an agent TUI.
    case windowTitle(String)
    /// OSC 7 — current working directory reported by shell integration.
    case workingDirectory(URL)
    /// OSC 133 — FinalTerm/iTerm2 semantic prompt marks (basis for blocks-lite).
    case semanticPrompt(SemanticPromptEvent)
    /// OSC 777 (`notify;title;body`) or OSC 99 (Kitty) — desktop notification.
    case notification(title: String, body: String)
    /// OSC 8 — clickable hyperlink. `params` carries key=value metadata (e.g.
    /// `id=mylink`); `uri` is the target URL. An empty URI signals hyperlink end.
    case hyperlink(uri: URL?, params: String)
    /// Any OSC code we recognized structurally but do not handle yet.
    case unhandled(code: Int, payload: String)
}

/// OSC 133 semantic prompt zones. `D` optionally carries the command exit code.
public enum SemanticPromptEvent: Equatable, Sendable {
    case promptStart            // 133;A
    case commandStart           // 133;B — user/agent started typing the command
    case outputStart            // 133;C — command execution began
    case commandEnd(exitCode: Int?) // 133;D[;code]
}

/// Incremental OSC parser. Feed it raw PTY bytes in arbitrary chunk sizes; it
/// extracts complete OSC sequences (`ESC ] ... BEL` or `ESC ] ... ESC \`) and
/// ignores everything else. Sequences split across chunk boundaries are handled.
///
/// This parser deliberately does not interpret any other VT sequences — full VT
/// parsing is the engine's job. It is a light tap on the stream for host-level
/// awareness (titles, cwd, prompts, notifications).
public struct OSCStreamParser: Sendable {
    /// Safety cap: OSC payloads longer than this are discarded, not buffered.
    public static let maxPayloadLength = 8192

    private enum State: Sendable {
        case ground
        case escape              // saw ESC, deciding
        case collecting          // inside OSC payload
        case collectingSawEscape // inside OSC payload, saw ESC (possible ST)
    }

    private var state: State = .ground
    private var payload: [UInt8] = []
    private var overflowed = false

    public init() {}

    /// Feed a chunk of bytes; returns all events completed within this chunk.
    public mutating func feed(_ bytes: some Sequence<UInt8>) -> [OSCEvent] {
        var events: [OSCEvent] = []
        for byte in bytes {
            switch state {
            case .ground:
                if byte == 0x1B { state = .escape }
            case .escape:
                if byte == UInt8(ascii: "]") {
                    state = .collecting
                    payload.removeAll(keepingCapacity: true)
                    overflowed = false
                } else {
                    state = .ground
                }
            case .collecting:
                if byte == 0x07 { // BEL terminator
                    finish(into: &events)
                } else if byte == 0x1B {
                    state = .collectingSawEscape
                } else {
                    append(byte)
                }
            case .collectingSawEscape:
                if byte == UInt8(ascii: "\\") { // ST terminator (ESC \)
                    finish(into: &events)
                } else if byte == UInt8(ascii: "]") {
                    // Broken sequence followed by a fresh OSC start.
                    payload.removeAll(keepingCapacity: true)
                    overflowed = false
                    state = .collecting
                } else {
                    // Stray ESC inside payload: treat the sequence as aborted.
                    state = byte == 0x1B ? .escape : .ground
                    payload.removeAll(keepingCapacity: true)
                }
            }
        }
        return events
    }

    private mutating func append(_ byte: UInt8) {
        guard !overflowed else { return }
        if payload.count >= Self.maxPayloadLength {
            overflowed = true
            payload.removeAll(keepingCapacity: false)
        } else {
            payload.append(byte)
        }
    }

    private mutating func finish(into events: inout [OSCEvent]) {
        defer {
            state = .ground
            payload.removeAll(keepingCapacity: true)
            overflowed = false
        }
        guard !overflowed, !payload.isEmpty,
              let text = String(bytes: payload, encoding: .utf8)
        else { return }
        if let event = Self.parse(text) {
            events.append(event)
        }
    }

    /// Parses one complete OSC payload (without ESC]/terminator), e.g. `133;D;0`.
    static func parse(_ text: String) -> OSCEvent? {
        guard let separator = text.firstIndex(where: { $0 == ";" }) ?? (Int(text) != nil ? text.endIndex : nil),
              let code = Int(text[text.startIndex..<separator])
        else { return nil }
        let rest = separator < text.endIndex ? String(text[text.index(after: separator)...]) : ""

        switch code {
        case 0, 2:
            return .windowTitle(rest)
        case 7:
            guard let url = URL(string: rest), url.scheme == "file" else {
                return .unhandled(code: 7, payload: rest)
            }
            return .workingDirectory(url)
        case 8:
            return parseHyperlink(rest)
        case 133:
            return parseSemanticPrompt(rest)
        case 777:
            return parseRichNotification(rest)
        case 99:
            return parseKittyNotification(rest)
        default:
            return .unhandled(code: code, payload: rest)
        }
    }

    private static func parseSemanticPrompt(_ rest: String) -> OSCEvent? {
        let parts = rest.split(separator: ";", omittingEmptySubsequences: false)
        guard let kind = parts.first?.prefix(1) else { return nil }
        switch kind {
        case "A": return .semanticPrompt(.promptStart)
        case "B": return .semanticPrompt(.commandStart)
        case "C": return .semanticPrompt(.outputStart)
        case "D":
            let exitCode = parts.count > 1 ? Int(parts[1]) : nil
            return .semanticPrompt(.commandEnd(exitCode: exitCode))
        default:
            return .unhandled(code: 133, payload: rest)
        }
    }

    /// OSC 777: `notify;<title>;<body>` (rxvt-unicode extension used by agent hooks).
    private static func parseRichNotification(_ rest: String) -> OSCEvent? {
        let parts = rest.split(separator: ";", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2, parts[0] == "notify" else {
            return .unhandled(code: 777, payload: rest)
        }
        let title = String(parts[1])
        let body = parts.count > 2 ? String(parts[2]) : ""
        return .notification(title: title, body: body)
    }

    /// OSC 99 (Kitty desktop notification, simplified): `<metadata>;<payload>`.
    /// Metadata is `key=value` pairs separated by `:`; we surface title/body parts
    /// (`p=title` vs `p=body`) and ignore multi-chunk continuation for now.
    private static func parseKittyNotification(_ rest: String) -> OSCEvent? {
        let parts = rest.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
        let metadata = parts.first.map(String.init) ?? ""
        let payload = parts.count > 1 ? String(parts[1]) : ""
        let isBody = metadata.split(separator: ":").contains { $0 == "p=body" }
        if isBody {
            return .notification(title: "", body: payload)
        }
        return .notification(title: payload, body: "")
    }

    /// OSC 8: `params;URI` (hyperlink start) or `;` (hyperlink end).
    private static func parseHyperlink(_ rest: String) -> OSCEvent {
        let parts = rest.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
        let params = parts.first.map(String.init) ?? ""
        let uriString = parts.count > 1 ? String(parts[1]) : ""
        let uri = uriString.isEmpty ? nil : URL(string: uriString)
        return .hyperlink(uri: uri, params: params)
    }
}
