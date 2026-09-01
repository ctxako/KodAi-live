import Foundation
import Testing
@testable import ToolGuardrails

@Suite("Tool call parser")
struct ToolCallParserTests {

    @Test("A valid call parses")
    func parsesValidCall() throws {
        let call = try ToolCallParser.parse(
            #"[{"name":"respond","arguments":{"message":"Hello"}}]"#
        )
        #expect(call == RawToolCall(name: "respond", arguments: ["message": "Hello"]))
    }

    @Test("An empty array is not a call")
    func rejectsEmptyArray() {
        #expect(throws: ToolCallParseError.noCalls) { try ToolCallParser.parse("[]") }
    }

    @Test("Two calls in one turn are refused")
    func rejectsMultipleCalls() {
        let json = """
        [{"name":"respond","arguments":{"message":"a"}},
         {"name":"respond","arguments":{"message":"b"}}]
        """
        #expect(throws: ToolCallParseError.multipleCalls(2)) { try ToolCallParser.parse(json) }
    }

    @Test("Malformed JSON fails cleanly")
    func rejectsMalformedJSON() {
        #expect(throws: ToolCallParseError.malformedJSON) {
            try ToolCallParser.parse(#"[{"name":"respond","arguments":{"#)
        }
    }

    @Test("A bare object is not an array of calls")
    func rejectsBareObject() {
        #expect(throws: ToolCallParseError.notAnArray) {
            try ToolCallParser.parse(#"{"name":"respond","arguments":{"message":"Hi"}}"#)
        }
    }

    @Test("JSON booleans normalize to \"true\" and \"false\"")
    func normalizesBooleans() throws {
        let on = try ToolCallParser.parse(
            #"[{"name":"calendar_create_event","arguments":{"title":"Retreat","start_date":"2026-09-01T00:00:00Z","all_day":true}}]"#
        )
        #expect(on.arguments["all_day"] == "true")

        let off = try ToolCallParser.parse(
            #"[{"name":"calendar_create_event","arguments":{"title":"Retreat","start_date":"2026-09-01T00:00:00Z","all_day":false}}]"#
        )
        #expect(off.arguments["all_day"] == "false")
    }

    @Test("Value types outside string and boolean are refused")
    func rejectsOtherValueTypes() {
        #expect(throws: ToolCallParseError.unsupportedArgumentValue(key: "title")) {
            try ToolCallParser.parse(#"[{"name":"reminders_create","arguments":{"title":42}}]"#)
        }
    }

    @Test("A call without name or arguments is refused")
    func rejectsIncompleteCalls() {
        #expect(throws: ToolCallParseError.missingName) {
            try ToolCallParser.parse(#"[{"arguments":{"message":"Hi"}}]"#)
        }
        #expect(throws: ToolCallParseError.missingArguments) {
            try ToolCallParser.parse(#"[{"name":"respond"}]"#)
        }
    }
}
