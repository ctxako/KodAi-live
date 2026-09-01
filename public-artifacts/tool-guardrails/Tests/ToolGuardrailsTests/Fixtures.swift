import Foundation
import Testing
@testable import ToolGuardrails

/// Loads `Fixtures/calendar-reminders-tools.json` from the package root.
///
/// Read off `#filePath` rather than declared as a bundle resource so the fixture
/// stays a plain, readable file at the top of the artifact rather than something
/// buried in the test target.
enum Fixtures {
    static func toolCatalog() throws -> [ToolDefinition] {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // ToolGuardrailsTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
        let url = packageRoot.appending(path: "Fixtures/calendar-reminders-tools.json")
        return try JSONDecoder().decode([ToolDefinition].self, from: Data(contentsOf: url))
    }
}

func date(_ iso: String) throws -> Date {
    try #require(ToolCallValidator.parseISO8601(iso))
}
