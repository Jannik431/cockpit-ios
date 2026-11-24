import Foundation

/// One stored answer. Encoded as a plain JSON value (number, bool, or "HH:MM" for times),
/// so exported data stays readable. The question catalog defines how a value is meant.
nonisolated enum AnswerValue: Codable, Sendable, Equatable, Hashable {
    case int(Int)
    case double(Double)
    case bool(Bool)
    /// Minutes since local midnight.
    case time(Int)
    /// Several option indices (multiple choice), sorted.
    case list([Int])

    var listValue: [Int]? {
        if case .list(let v) = self { return v }
        return nil
    }

    var intValue: Int? {
        switch self {
        case .int(let v): v
        case .double(let v): Int(v.rounded())
        default: nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .int(let v): Double(v)
        case .double(let v): v
        default: nil
        }
    }

    var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }

    var minutes: Int? {
        if case .time(let v) = self { return v }
        return nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let list = try? container.decode([Int].self) {
            self = .list(list)
        } else {
            let text = try container.decode(String.self)
            let parts = text.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2 else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown answer value \(text)")
            }
            self = .time(parts[0] * 60 + parts[1])
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .time(let v): try container.encode(String(format: "%02d:%02d", v / 60, v % 60))
        case .list(let v): try container.encode(v)
        }
    }
}
