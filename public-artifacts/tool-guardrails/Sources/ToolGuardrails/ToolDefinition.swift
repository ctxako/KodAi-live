import Foundation

/// The value shapes a tool argument may take.
///
/// Deliberately tiny: a local 1–2B model fills these reliably, and every richer
/// type (dates, enums, ids) is better checked by the semantic validator than by
/// a grammar. Dates therefore travel as `.string` and are parsed downstream.
public enum ArgumentType: String, Codable, Sendable, Equatable {
    case string
    case boolean
}

/// One named argument of a tool.
public struct ToolArgument: Codable, Sendable, Equatable {
    public let name: String
    public let type: ArgumentType
    public let isRequired: Bool

    public init(name: String, type: ArgumentType, isRequired: Bool) {
        self.name = name
        self.type = type
        self.isRequired = isRequired
    }

    private enum CodingKeys: String, CodingKey {
        case name, type
        case isRequired = "required"
    }
}

/// A tool the model is allowed to call.
///
/// The catalog is the single source of truth: the grammar compiler derives what
/// the sampler may emit from it, and the validator derives what may be proposed
/// from it. Adding a tool in one place cannot leave the other behind.
public struct ToolDefinition: Codable, Sendable, Equatable {
    public let name: String
    public let summary: String
    public let arguments: [ToolArgument]

    public init(name: String, summary: String, arguments: [ToolArgument]) {
        self.name = name
        self.summary = summary
        self.arguments = arguments
    }

    public var requiredArguments: [ToolArgument] { arguments.filter(\.isRequired) }
    public var optionalArguments: [ToolArgument] { arguments.filter { !$0.isRequired } }
}

extension ToolDefinition {
    /// The three tools this reference artifact demonstrates.
    public static let exampleCatalog: [ToolDefinition] = [
        ToolDefinition(
            name: "calendar_create_event",
            summary: "Create a calendar event.",
            arguments: [
                ToolArgument(name: "title", type: .string, isRequired: true),
                ToolArgument(name: "start_date", type: .string, isRequired: true),
                ToolArgument(name: "end_date", type: .string, isRequired: false),
                ToolArgument(name: "all_day", type: .boolean, isRequired: false),
            ]
        ),
        ToolDefinition(
            name: "reminders_create",
            summary: "Create a reminder.",
            arguments: [
                ToolArgument(name: "title", type: .string, isRequired: true),
                ToolArgument(name: "due_date", type: .string, isRequired: false),
            ]
        ),
        ToolDefinition(
            name: "respond",
            summary: "Answer the user in plain language without touching any store.",
            arguments: [
                ToolArgument(name: "message", type: .string, isRequired: true)
            ]
        ),
    ]
}
