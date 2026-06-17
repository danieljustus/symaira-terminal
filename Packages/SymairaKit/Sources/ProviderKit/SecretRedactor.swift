import Foundation

public struct RedactionResult: Sendable, Equatable {
    public let text: String
    public let redactionCount: Int
    public let wasTruncated: Bool
    public let originalByteCount: Int

    public var displayText: String {
        var result = text
        if wasTruncated {
            result += "\n\n[... output truncated — \(originalByteCount - text.utf8.count) bytes omitted ...]"
        }
        return result
    }
}

public struct SecretRedactor: Sendable {
    public static let defaultMaxBytes = 16_000

    private let maxBytes: Int

    public init(maxBytes: Int = Self.defaultMaxBytes) {
        self.maxBytes = maxBytes
    }

    public func redact(_ input: String) -> RedactionResult {
        var text = input
        var count = 0

        for pattern in Self.patterns {
            let (newText, replacements) = replaceAll(text, pattern: pattern.regex, replacement: pattern.replacement)
            if replacements > 0 {
                text = newText
                count += replacements
            }
        }

        let originalBytes = text.utf8.count
        let truncated = truncate(text, maxBytes: maxBytes)

        return RedactionResult(
            text: truncated,
            redactionCount: count,
            wasTruncated: truncated.utf8.count < originalBytes,
            originalByteCount: originalBytes
        )
    }

    private static let patterns: [(regex: NSRegularExpression, replacement: String)] = {
        let raw: [(pattern: String, replacement: String)] = [
            // Anthropic keys: sk-ant-...
            ("sk-ant-[A-Za-z0-9_-]{20,}", "[REDACTED:anthropic-key]"),
            // OpenAI keys: sk-... or sk-proj-...
            ("sk-proj-[A-Za-z0-9]{20,}", "[REDACTED:openai-key]"),
            ("sk-[A-Za-z0-9]{20,}", "[REDACTED:openai-key]"),
            // GitHub tokens: ghp_, gho_, ghu_, ghs_, ghr_
            ("gh[pousr]_[A-Za-z0-9]{36,}", "[REDACTED:github-token]"),
            // GitLab tokens: glpat-
            ("glpat-[A-Za-z0-9_-]{20,}", "[REDACTED:gitlab-token]"),
            // Slack tokens: xoxb-, xoxp-, xoxa-, xoxr-, xoxs-, xapp-
            ("xox[bpars]-[A-Za-z0-9-]+", "[REDACTED:slack-token]"),
            // Stripe keys: sk_live_, sk_test_, rk_live_, rk_test_
            ("[sr]k_(live|test)_[A-Za-z0-9]{20,}", "[REDACTED:stripe-key]"),
            // AWS access keys: AKIA... or ASIA...
            ("(AKIA|ASIA)[A-Z0-9]{16}", "[REDACTED:aws-key]"),
            // Google API keys: AIza...
            ("AIza[A-Za-z0-9_-]{35}", "[REDACTED:google-key]"),
            // Generic Bearer tokens in headers
            ("(?i)Bearer\\s+[A-Za-z0-9._~-]{20,}", "Bearer [REDACTED:token]"),
            // Generic Authorization headers
            ("(?i)(Authorization|X-Api-Key|Api-Key):\\s*[\"']?[^\\s\"']{8,}[\"']?", "$1: [REDACTED]"),
            // Environment variable assignments with common secret names
            ("(?i)(API_KEY|SECRET_KEY|PRIVATE_KEY|ACCESS_TOKEN|AUTH_TOKEN|PASSWORD|SECRET)=[\"']?[^\\s\"']{4,}[\"']?", "$1=[REDACTED]"),
            // Private key file paths
            ("(?i)(id_rsa|id_ed25519|id_ecdsa|\\.pem|\\.key)(?=[\\s\"':]|$)", "[REDACTED:key-file]"),
            // Base64-encoded blocks that look like keys (40+ chars, require delimiters)
            ("(?<=[=: ])[A-Za-z0-9+/]{40,}={0,2}(?=[\\s\"':,])", "[REDACTED:base64-secret]")
        ]

        return raw.compactMap { entry in
            guard let regex = try? NSRegularExpression(pattern: entry.pattern, options: []) else { return nil }
            return (regex, entry.replacement)
        }
    }()

    private func replaceAll(_ text: String, pattern: NSRegularExpression, replacement: String) -> (String, Int) {
        let range = NSRange(text.startIndex..., in: text)
        var count = 0
        let result = pattern.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: replacement
        )
        count = pattern.numberOfMatches(in: text, options: [], range: range)
        return (result, count)
    }

    private func truncate(_ text: String, maxBytes: Int) -> String {
        guard text.utf8.count > maxBytes else { return text }
        var result = ""
        var byteCount = 0
        for char in text {
            let charBytes = char.utf8.count
            if byteCount + charBytes > maxBytes { break }
            result.append(char)
            byteCount += charBytes
        }
        return result
    }
}
