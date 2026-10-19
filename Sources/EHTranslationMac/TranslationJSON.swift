#if os(macOS)
import Foundation

/// Lossless JSON keeps upstream extensions and per-model parameter descriptors.
public enum TranslationJSON: Codable, Hashable, Sendable {
    case object([String: TranslationJSON]), array([TranslationJSON]), string(String), number(Double), bool(Bool), null

    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let item = try? value.decode(Bool.self) { self = .bool(item) }
        else if let item = try? value.decode(Double.self) { self = .number(item) }
        else if let item = try? value.decode(String.self) { self = .string(item) }
        else if let item = try? value.decode([String: TranslationJSON].self) { self = .object(item) }
        else { self = .array(try value.decode([TranslationJSON].self)) }
    }

    public func encode(to encoder: any Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .object(let item): try value.encode(item)
        case .array(let item): try value.encode(item)
        case .string(let item): try value.encode(item)
        case .number(let item): try value.encode(item)
        case .bool(let item): try value.encode(item)
        case .null: try value.encodeNil()
        }
    }

    public var object: [String: TranslationJSON] { if case .object(let item) = self { item } else { [:] } }
    public var array: [TranslationJSON] { if case .array(let item) = self { item } else { [] } }
    public var string: String {
        switch self { case .string(let value): value; case .number(let value): String(value); default: "" }
    }
    public var bool: Bool { if case .bool(let item) = self { item } else { false } }
    public var number: Double { if case .number(let item) = self { item } else { 0 } }
    var isParameterDescriptor: Bool { object["value"] != nil && self["storage"].string != "portable_obfuscated" }
    public subscript(_ key: String) -> TranslationJSON {
        get { object[key] ?? .null }
        set { var values = object; values[key] = newValue; self = .object(values) }
    }
    public subscript(path path: [String]) -> TranslationJSON {
        get { path.reduce(self) { $0[$1] } }
        set {
            guard let first = path.first else { self = newValue; return }
            var child = self[first]
            child[path: Array(path.dropFirst())] = newValue
            self[first] = child
        }
    }
}
#endif
