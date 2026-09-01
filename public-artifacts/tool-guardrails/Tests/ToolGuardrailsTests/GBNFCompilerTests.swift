import Foundation
import Testing
@testable import ToolGuardrails

@Suite("GBNF compiler")
struct GBNFCompilerTests {

    @Test("The fixture catalog is the catalog under test")
    func fixtureMatchesExampleCatalog() throws {
        #expect(try Fixtures.toolCatalog() == ToolDefinition.exampleCatalog)
    }

    @Test("Compilation is deterministic")
    func deterministic() throws {
        let tools = try Fixtures.toolCatalog()
        let first = try GBNFCompiler.compile(tools)
        let second = try GBNFCompiler.compile(tools)
        #expect(first == second)
    }

    @Test("Grammar names every catalogued tool")
    func containsEveryToolName() throws {
        let grammar = try GBNFCompiler.compile(Fixtures.toolCatalog())
        for name in ["calendar_create_event", "reminders_create", "respond"] {
            #expect(grammar.contains("\"\\\"\(name)\\\"\""))
        }
    }

    @Test("Only catalogued tools appear")
    func rejectsUncataloguedNames() throws {
        let grammar = try GBNFCompiler.compile(Fixtures.toolCatalog())
        #expect(!grammar.contains("calendar_delete_event"))
        #expect(grammar.contains("call ::= tool-calendar-create-event | tool-reminders-create | tool-respond"))
    }

    @Test("Required event fields are mandatory and optional ones are guarded")
    func requiredFieldHandling() throws {
        let grammar = try GBNFCompiler.compile(Fixtures.toolCatalog())
        let argsRule = try #require(
            grammar.split(separator: "\n")
                .first { $0.hasPrefix("tool-calendar-create-event-args ::=") }
                .map(String.init)
        )

        // title and start_date are unguarded; end_date and all_day carry `?`.
        #expect(argsRule.contains("tool-calendar-create-event-title ws \",\" ws tool-calendar-create-event-start-date"))
        #expect(!argsRule.contains("(tool-calendar-create-event-title)?"))
        #expect(argsRule.contains("(ws \",\" ws tool-calendar-create-event-end-date)?"))
        #expect(argsRule.contains("(ws \",\" ws tool-calendar-create-event-all-day)?"))
    }

    @Test("Argument keys are typed: booleans are not strings")
    func booleanArgumentsUseBooleanRule() throws {
        let grammar = try GBNFCompiler.compile(Fixtures.toolCatalog())
        #expect(grammar.contains("tool-calendar-create-event-all-day ::= \"\\\"all_day\\\"\" ws \":\" ws boolean"))
        #expect(grammar.contains("tool-respond-message ::= \"\\\"message\\\"\" ws \":\" ws string"))
    }

    @Test("A single call in brackets is the only accepted top-level shape")
    func rootIsASingleBracketedCall() throws {
        let grammar = try GBNFCompiler.compile(Fixtures.toolCatalog())
        #expect(grammar.contains("root ::= \"[\" ws call ws \"]\""))
    }

    @Test("A malformed catalog is refused")
    func refusesMalformedCatalogs() {
        #expect(throws: GBNFCompilerError.emptyCatalog) { try GBNFCompiler.compile([]) }

        let duplicated = [ToolDefinition.exampleCatalog[2], ToolDefinition.exampleCatalog[2]]
        #expect(throws: GBNFCompilerError.duplicateToolName("respond")) {
            try GBNFCompiler.compile(duplicated)
        }
    }
}
