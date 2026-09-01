import Foundation

/// What the model asked for, once it is known to make sense.
public enum ToolAction: Equatable, Sendable {
    case createEvent(title: String, start: Date, end: Date?, isAllDay: Bool)
    case createReminder(title: String, due: Date?)
    case respond(message: String)
}

/// A checked call. Holding one means the request was well-formed and coherent —
/// not that anything happened.
public struct ValidatedToolCall: Equatable, Sendable {
    public let name: String
    public let action: ToolAction

    public init(name: String, action: ToolAction) {
        self.name = name
        self.action = action
    }

    /// True when acting on this call would write to a user's data, and a UI must
    /// therefore put it in front of the user before anything is committed.
    public var isWrite: Bool {
        switch action {
        case .createEvent, .createReminder: true
        case .respond: false
        }
    }
}

public enum ValidationError: Error, Equatable, Sendable {
    case unknownTool(String)
    case missingRequiredArgument(tool: String, argument: String)
    case emptyValue(argument: String)
    case invalidDate(argument: String, value: String)
    case endNotAfterStart
    case eventInThePast
    case invalidBoolean(argument: String, value: String)
}

/// The outcome of validation.
///
/// There is deliberately no `case executed`. The success case is a *proposal*:
/// something to show the user, who is the only party that can turn it into a
/// write.
public enum ValidationResult: Equatable, Sendable {
    case proposal(ValidatedToolCall)
    case rejection(ValidationError)
}

/// Decides whether a parsed call is safe to propose.
///
/// This is where everything a grammar cannot express is enforced: that a date
/// string is really a date, that an event ends after it starts, that the model
/// has not confidently scheduled lunch for last Tuesday. `now` is injected
/// rather than read from the clock so that "is this in the past" is a testable
/// question with a fixed answer.
public struct ToolCallValidator: Sendable {
    private let now: Date
    private let catalog: [String: ToolDefinition]

    public init(now: Date, catalog: [ToolDefinition] = ToolDefinition.exampleCatalog) {
        self.now = now
        self.catalog = Dictionary(uniqueKeysWithValues: catalog.map { ($0.name, $0) })
    }

    public func validate(_ call: RawToolCall) -> ValidationResult {
        guard let tool = catalog[call.name] else {
            return .rejection(.unknownTool(call.name))
        }

        for argument in tool.requiredArguments where call.arguments[argument.name] == nil {
            return .rejection(.missingRequiredArgument(tool: tool.name, argument: argument.name))
        }

        do {
            let action = switch call.name {
            case "calendar_create_event": try validateEvent(call)
            case "reminders_create": try validateReminder(call)
            case "respond": try validateRespond(call)
            default: throw ValidationError.unknownTool(call.name)
            }
            return .proposal(ValidatedToolCall(name: call.name, action: action))
        } catch let error as ValidationError {
            return .rejection(error)
        } catch {
            return .rejection(.unknownTool(call.name))
        }
    }

    // MARK: - Per-tool semantics

    private func validateEvent(_ call: RawToolCall) throws -> ToolAction {
        let title = try nonEmpty(call.arguments["title"], argument: "title")
        let start = try date(call.arguments["start_date"], argument: "start_date")

        // A model that misreads "tomorrow" produces a perfectly shaped call for
        // a date that has already gone by. Nothing downstream would notice.
        guard start >= now else { throw ValidationError.eventInThePast }

        var end: Date?
        if let raw = call.arguments["end_date"] {
            let parsed = try date(raw, argument: "end_date")
            guard parsed > start else { throw ValidationError.endNotAfterStart }
            end = parsed
        }

        var isAllDay = false
        if let raw = call.arguments["all_day"] {
            isAllDay = try boolean(raw, argument: "all_day")
        }

        return .createEvent(title: title, start: start, end: end, isAllDay: isAllDay)
    }

    private func validateReminder(_ call: RawToolCall) throws -> ToolAction {
        let title = try nonEmpty(call.arguments["title"], argument: "title")
        // Unlike an event, a reminder for a past moment is a legitimate thing to
        // want, so only the parse is enforced.
        let due = try call.arguments["due_date"].map { try date($0, argument: "due_date") }
        return .createReminder(title: title, due: due)
    }

    private func validateRespond(_ call: RawToolCall) throws -> ToolAction {
        .respond(message: try nonEmpty(call.arguments["message"], argument: "message"))
    }

    // MARK: - Field helpers

    private func nonEmpty(_ value: String?, argument: String) throws -> String {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ValidationError.emptyValue(argument: argument) }
        return trimmed
    }

    private func boolean(_ value: String, argument: String) throws -> Bool {
        switch value {
        case "true": true
        case "false": false
        default: throw ValidationError.invalidBoolean(argument: argument, value: value)
        }
    }

    private func date(_ value: String?, argument: String) throws -> Date {
        let raw = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { throw ValidationError.emptyValue(argument: argument) }
        guard let parsed = Self.parseISO8601(raw) else {
            throw ValidationError.invalidDate(argument: argument, value: raw)
        }
        return parsed
    }

    /// ISO-8601 only, with or without fractional seconds. Accepting looser
    /// formats here would move date interpretation back into the model, which is
    /// the thing worth avoiding: the app should decide what "noon tomorrow"
    /// means, not the 1.2B parameters that wrote the string.
    static func parseISO8601(_ value: String) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: value) { return date }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value)
    }
}
