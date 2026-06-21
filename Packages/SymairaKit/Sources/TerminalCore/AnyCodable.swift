import Foundation

/// A type-erased `Codable` value that conforms to `Sendable`.
///
/// Unifies the two previous `AnyCodable` implementations (AgentKit and MCPKit)
/// into a single canonical type. Supports nested arrays and dictionaries
/// during decoding, unlike the MCPKit-only predecessor.
///
/// The stored `value` is always a `Sendable` type: `Bool`, `Int`, `Double`,
/// `String`, `[AnyCodable]`, `[String: AnyCodable]`, or ``NullValue``.
public struct AnyCodable: Codable, Sendable {

    /// The underlying value, guaranteed to be `Sendable`.
    public let value: any Sendable

    /// Create from any `Sendable` value.
    public init(_ value: some Sendable) {
        self.value = value
    }

    // MARK: - Decodable

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NullValue.null
        } else if let v = try? container.decode(Bool.self) {
            value = v
        } else if let v = try? container.decode(Int.self) {
            value = v
        } else if let v = try? container.decode(Double.self) {
            value = v
        } else if let v = try? container.decode(String.self) {
            value = v
        } else if let v = try? container.decode([AnyCodable].self) {
            value = v
        } else if let v = try? container.decode([String: AnyCodable].self) {
            value = v
        } else {
            value = NullValue.null
        }
    }

    // MARK: - Encodable

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as Bool:
            try container.encode(v)
        case let v as Int:
            try container.encode(v)
        case let v as Double:
            try container.encode(v)
        case let v as String:
            try container.encode(v)
        case let v as [AnyCodable]:
            try container.encode(v)
        case let v as [String: AnyCodable]:
            try container.encode(v)
        case _ as NullValue:
            try container.encodeNil()
        default:
            try container.encodeNil()
        }
    }
}

// MARK: - Null sentinel

/// Sendable sentinel for JSON `null` values.
///
/// `NSNull` is not reliably `Sendable` across all Swift toolchain versions,
/// so we use a zero-case enum instead.
public enum NullValue: Sendable, Codable {
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard container.decodeNil() else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected null")
        }
        self = .null
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encodeNil()
    }
}
