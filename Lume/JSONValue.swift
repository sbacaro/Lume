import Foundation

/// A type that can represent any JSON value.
public enum JSONValue: Codable, Equatable, Sendable {
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
    case null
    
    // MARK: - Codable
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch self {
        case .bool(let bool):
            try container.encode(bool)
        case .number(let number):
            try container.encode(number)
        case .string(let string):
            try container.encode(string)
        case .array(let array):
            try container.encode(array)
        case .object(let object):
            try container.encode(object)
        case .null:
            try container.encodeNil()
        }
    }
    
    // MARK: - Convenience Accessors
    
    /// Returns a boolean value for this JSON value, or `nil` if not a boolean.
    var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }
    
    /// Returns a numeric value for this JSON value, or `nil` if not a number.
    var number: Double? {
        if case .number(let value) = self { return value }
        return nil
    }
    
    /// Returns a string value for this JSON value, or `nil` if not a string.
    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }
    
    /// Returns a string value for this JSON value, or `nil` if not a string.
    /// Computed property for backward compatibility during migration.
    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
    
    /// Returns an array value for this JSON value, or `nil` if not an array.
    var array: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }
    
    /// Returns an object value for this JSON value, or `nil` if not an object.
    var object: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }
    
    /// Returns whether this JSON value is null.
    var isNull: Bool {
        if case .null = self { return true }
        return false
    }
    
    // MARK: - Subscript
    
    /// Accesses the value associated with the given key for object JSON values.
    subscript(key: String) -> JSONValue? {
        get {
            return object?[key]
        }
        set {
            if var obj = object {
                if let newValue = newValue {
                    obj[key] = newValue
                } else {
                    obj.removeValue(forKey: key)
                }
                self = .object(obj)
            }
        }
    }
    
    /// Accesses the value at the given index for array JSON values.
    subscript(index: Int) -> JSONValue? {
        get {
            return array?[index]
        }
        set {
            if var arr = array {
                if let newValue = newValue {
                    arr[index] = newValue
                } else {
                    arr.remove(at: index)
                }
                self = .array(arr)
            }
        }
    }
}