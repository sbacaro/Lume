//
//  JSONValueTests.swift
//  LumeTests
//
//  Cobre o tipo JSONValue: round-trip Codable, acessores e subscripts.
//

import Testing
import Foundation
@testable import Lume

struct JSONValueTests {

    // MARK: - Accessors

    @Test func accessorsReturnUnderlyingValues() {
        #expect(JSONValue.bool(true).bool == true)
        #expect(JSONValue.number(42).number == 42)
        #expect(JSONValue.string("oi").string == "oi")
        #expect(JSONValue.string("oi").stringValue == "oi")
        #expect(JSONValue.null.isNull)
        #expect(JSONValue.array([.number(1)]).array?.count == 1)
        #expect(JSONValue.object(["k": .string("v")]).object?["k"]?.string == "v")
    }

    @Test func accessorsReturnNilOnTypeMismatch() {
        #expect(JSONValue.string("x").bool == nil)
        #expect(JSONValue.bool(true).number == nil)
        #expect(JSONValue.null.string == nil)
    }

    // MARK: - Subscripts

    @Test func objectSubscriptGetAndSet() {
        var value = JSONValue.object(["a": .number(1)])
        #expect(value["a"]?.number == 1)
        value["b"] = .string("nova")
        #expect(value["b"]?.string == "nova")
        value["a"] = nil
        #expect(value["a"] == nil)
    }

    @Test func arraySubscriptGet() {
        let value = JSONValue.array([.string("zero"), .string("um")])
        #expect(value[0]?.string == "zero")
        #expect(value[1]?.string == "um")
    }

    // MARK: - Codable round-trip

    @Test func encodeDecodeRoundTrip() throws {
        let original = JSONValue.object([
            "name": .string("Lume"),
            "version": .number(6),
            "stable": .bool(true),
            "tags": .array([.string("ai"), .string("macos")]),
            "extra": .null,
        ])

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)

        #expect(decoded == original)
    }

    @Test func decodeFromRawJSON() throws {
        let json = #"{"id":1,"ok":true,"label":"x"}"#.data(using: .utf8)!
        let value = try JSONDecoder().decode(JSONValue.self, from: json)
        #expect(value["id"]?.number == 1)
        #expect(value["ok"]?.bool == true)
        #expect(value["label"]?.string == "x")
    }
}
