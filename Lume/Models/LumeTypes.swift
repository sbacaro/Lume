//
//  LumeTypes.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//
//  Shared types used by Backend, EngineManager and tool infrastructure.

import Foundation

// MARK: - Errors

enum LumeError: LocalizedError {
    case server(String)
    case cancelled
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .server(let msg):  return msg
        case .cancelled:        return "Cancelled"
        case .unknown(let msg): return msg
        }
    }
}

// MARK: - Tool types

struct ToolCallRecord: Identifiable {
    let id = UUID()
    let name: String
    let arguments: [String: JSONValue]
}

struct ToolSpec: Encodable {
    struct Fn: Encodable {
        var name: String
        var description: String
        var parameters: JSONValue
    }
    var type = "function"
    var function: Fn
}
