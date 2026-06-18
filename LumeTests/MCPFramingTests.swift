//
//  MCPFramingTests.swift
//  LumeTests
//
//  Cobre o núcleo puro do cliente MCP: framing newline-delimited e decode JSON-RPC.
//

import Testing
import Foundation
@testable import Lume

@MainActor
struct MCPFramingTests {

    // MARK: - frame

    @Test func frameAppendsNewlineAndIsValidJSON() throws {
        let data = try MCPFraming.frame(["jsonrpc": "2.0", "id": 1, "method": "ping"])
        #expect(data.last == 0x0A)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["method"] as? String == "ping")
        #expect(obj?["id"] as? Int == 1)
    }

    // MARK: - extractLines

    @Test func extractLinesSplitsCompleteMessages() {
        var buffer = Data("a\nbb\nccc\n".utf8)
        let lines = MCPFraming.extractLines(from: &buffer)
        #expect(lines.map { String(decoding: $0, as: UTF8.self) } == ["a", "bb", "ccc"])
        #expect(buffer.isEmpty)
    }

    @Test func extractLinesKeepsPartialRemainder() {
        var buffer = Data("first\nsecond".utf8)
        let lines = MCPFraming.extractLines(from: &buffer)
        #expect(lines.map { String(decoding: $0, as: UTF8.self) } == ["first"])
        // "second" (sem \n) permanece no buffer.
        #expect(String(decoding: buffer, as: UTF8.self) == "second")
    }

    @Test func extractLinesReassemblesAcrossChunks() {
        var buffer = Data("hel".utf8)
        #expect(MCPFraming.extractLines(from: &buffer).isEmpty)
        buffer.append(Data("lo\n".utf8))
        let lines = MCPFraming.extractLines(from: &buffer)
        #expect(lines.map { String(decoding: $0, as: UTF8.self) } == ["hello"])
        #expect(buffer.isEmpty)
    }

    @Test func extractLinesSkipsEmptyLines() {
        var buffer = Data("\n\n".utf8)
        #expect(MCPFraming.extractLines(from: &buffer).isEmpty)
        #expect(buffer.isEmpty)
    }

    // MARK: - decode (JSON-RPC)

    @Test func decodeResultResponse() throws {
        let line = Data(#"{"jsonrpc":"2.0","id":1,"result":{"tools":[{"name":"x"}]}}"#.utf8)
        let resp = try #require(MCPFraming.decode(line))
        #expect(resp.id == 1)
        #expect(resp.error == nil)
        #expect(resp.result?["tools"]?.array?.count == 1)
    }

    @Test func decodeErrorResponse() throws {
        let line = Data(#"{"jsonrpc":"2.0","id":2,"error":{"code":-32601,"message":"Method not found"}}"#.utf8)
        let resp = try #require(MCPFraming.decode(line))
        #expect(resp.id == 2)
        #expect(resp.error?.code == -32601)
        #expect(resp.error?.message == "Method not found")
    }

    @Test func decodeGarbageReturnsNil() {
        #expect(MCPFraming.decode(Data("not json".utf8)) == nil)
    }

    // MARK: - MCPToolInfo

    @Test func toolInfoParsesFromJSON() throws {
        let json = #"{"name":"search","description":"Find things","inputSchema":{"type":"object"}}"#
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        let info = try #require(MCPToolInfo(json: value))
        #expect(info.name == "search")
        #expect(info.description == "Find things")
        #expect(info.inputSchema["type"]?.string == "object")
    }

    @Test func toolInfoRequiresName() throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"description":"x"}"#.utf8))
        #expect(MCPToolInfo(json: value) == nil)
    }

    // MARK: - MCPAgentTool schema → parameters

    @Test func schemaMapsToParameters() throws {
        let schema = """
        {"type":"object",
         "properties":{
           "path":{"type":"string","description":"File path"},
           "depth":{"type":"number","description":"How deep"}
         },
         "required":["path"]}
        """
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(schema.utf8))
        let params = MCPAgentTool.parameters(from: value)
        // ordenados por nome: depth, path
        #expect(params.map(\.name) == ["depth", "path"])
        let path = try #require(params.first { $0.name == "path" })
        #expect(path.type == "string")
        #expect(path.description == "File path")
        #expect(path.required == true)
        let depth = try #require(params.first { $0.name == "depth" })
        #expect(depth.required == false)
    }

    @Test func schemaWithoutPropertiesIsEmpty() {
        #expect(MCPAgentTool.parameters(from: .object([:])).isEmpty)
    }
}
