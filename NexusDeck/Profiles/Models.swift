import Foundation

/// Loosely typed JSON value used for per-action settings.
enum JSONValue: Codable, Hashable {
    case string(String), number(Double), bool(Bool), array([JSONValue]), object([String: JSONValue]), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        case .null: try c.encodeNil()
        }
    }

    var string: String? { if case .string(let s) = self { s } else { nil } }
    var double: Double? { if case .number(let n) = self { n } else { nil } }
    var int: Int? { double.map { Int($0) } }
    var bool: Bool? { if case .bool(let b) = self { b } else { nil } }
    var array: [JSONValue]? { if case .array(let a) = self { a } else { nil } }
    var object: [String: JSONValue]? { if case .object(let o) = self { o } else { nil } }
}

typealias Settings = [String: JSONValue]

extension Dictionary where Key == String, Value == JSONValue {
    func string(_ k: String, _ d: String = "") -> String { self[k]?.string ?? d }
    func int(_ k: String, _ d: Int = 0) -> Int { self[k]?.int ?? d }
    func double(_ k: String, _ d: Double = 0) -> Double { self[k]?.double ?? d }
    func bool(_ k: String, _ d: Bool = false) -> Bool { self[k]?.bool ?? d }
}

/// Text style drawn on a key.
struct KeyTitleStyle: Codable, Hashable {
    var colorHex = "#FFFFFF"
    var size: Double = 13
    var bold = false
    var italic = false
    var underline = false
    var alignment: Alignment = .bottom
    var fontFamily = ""
    var textAlignment: HAlign = .center

    enum Alignment: String, Codable, CaseIterable { case top, middle, bottom }
    enum HAlign: String, Codable, CaseIterable { case leading, center, trailing }
}

/// Visual state of a key (multi-state actions such as toggles have several).
struct KeyState: Codable, Hashable {
    var title: String = ""
    /// File name of a user image inside the app icon folder, or an SF Symbol prefixed with "sf:".
    var image: String = ""
    var background: String = "#202024"
}

enum SlotKind: String, Codable { case touch, functionKey }

/// Special page values.
enum PageID {
    /// Children of a group folder live on pages >= this base: groupBase + index.
    static let groupBase = 1000
}

/// An action/widget placed on the panel.
struct KeyAssignment: Codable, Identifiable, Hashable {
    var id = UUID()
    var actionID: String
    var slot: SlotKind = .touch
    var page: Int = 0
    var x: Int = 0
    var y: Int = 0
    var w: Int = 1
    var h: Int = 1
    var states: [KeyState] = [KeyState()]
    var style = KeyTitleStyle()
    var settings: Settings = [:]
    /// For multi-action: ordered child actions.
    var children: [KeyAssignment] = []

    func covers(x cx: Int, y cy: Int) -> Bool { cx >= x && cx < x + w && cy >= y && cy < y + h }
}

struct HotkeyProfile: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var pageCount: Int = 5
    var keys: [KeyAssignment] = []
    /// Number of group folders created (each owns page groupBase + n).
    var groupCounter: Int = 0
}

// MARK: Knobs

struct KnobAssignment: Codable, Hashable, Identifiable {
    var id: Int { index }
    var index: Int
    /// nil = hardware mixer channel (default behaviour)
    var actionID: String?
    var settings: Settings = [:]
}

struct KnobProfile: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var knobs: [KnobAssignment] = (0..<6).map { KnobAssignment(index: $0) }
}
