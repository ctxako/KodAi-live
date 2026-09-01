import Foundation
import Testing
@testable import ToolGuardrails

@Suite("Semantic validator")
struct ToolCallValidatorTests {

    /// Every time-sensitive test is anchored here, so "in the past" never
    /// depends on when the suite runs.
    static let now = try! date("2026-09-01T09:00:00Z")
    let validator = ToolCallValidator(now: ToolCallValidatorTests.now)

    private func validate(_ name: String, _ arguments: [String: String]) -> ValidationResult {
        validator.validate(RawToolCall(name: name, arguments: arguments))
    }

    @Test("An unknown tool is rejected")
    func rejectsUnknownTool() {
        #expect(validate("calendar_delete_event", [:]) == .rejection(.unknownTool("calendar_delete_event")))
    }

    @Test("A missing event title is rejected")
    func rejectsMissingTitle() {
        let result = validate("calendar_create_event", ["start_date": "2026-09-02T12:00:00Z"])
        #expect(result == .rejection(.missingRequiredArgument(tool: "calendar_create_event", argument: "title")))
    }

    @Test("A whitespace-only title is rejected")
    func rejectsBlankTitle() {
        let result = validate("calendar_create_event", ["title": "   ", "start_date": "2026-09-02T12:00:00Z"])
        #expect(result == .rejection(.emptyValue(argument: "title")))
    }

    @Test("A date the model wrote in prose is rejected")
    func rejectsInvalidDate() {
        let result = validate("calendar_create_event", ["title": "Lunch", "start_date": "tomorrow at noon"])
        #expect(result == .rejection(.invalidDate(argument: "start_date", value: "tomorrow at noon")))
    }

    @Test("An end date at or before the start is rejected")
    func rejectsEndBeforeStart() {
        let earlier = validate("calendar_create_event", [
            "title": "Lunch",
            "start_date": "2026-09-02T12:00:00Z",
            "end_date": "2026-09-02T11:00:00Z",
        ])
        #expect(earlier == .rejection(.endNotAfterStart))

        let identical = validate("calendar_create_event", [
            "title": "Lunch",
            "start_date": "2026-09-02T12:00:00Z",
            "end_date": "2026-09-02T12:00:00Z",
        ])
        #expect(identical == .rejection(.endNotAfterStart))
    }

    @Test("An event in the past is rejected against the injected clock")
    func rejectsPastEvent() {
        let result = validate("calendar_create_event", [
            "title": "Lunch with Sam",
            "start_date": "2026-08-25T12:00:00Z",
        ])
        #expect(result == .rejection(.eventInThePast))
    }

    @Test("A valid future event becomes a proposal")
    func acceptsFutureEvent() throws {
        let result = validate("calendar_create_event", [
            "title": "Lunch with Sam",
            "start_date": "2026-09-01T12:00:00-04:00",
            "end_date": "2026-09-01T13:00:00-04:00",
            "all_day": "false",
        ])

        guard case .proposal(let call) = result else {
            Issue.record("expected a proposal, got \(result)")
            return
        }
        #expect(call.name == "calendar_create_event")
        #expect(call.isWrite)
        #expect(call.action == .createEvent(
            title: "Lunch with Sam",
            start: try date("2026-09-01T16:00:00Z"),
            end: try date("2026-09-01T17:00:00Z"),
            isAllDay: false
        ))
    }

    @Test("A boolean that did not come from JSON is rejected")
    func rejectsNonBooleanFlag() {
        let result = validate("calendar_create_event", [
            "title": "Retreat",
            "start_date": "2026-09-02T12:00:00Z",
            "all_day": "yes",
        ])
        #expect(result == .rejection(.invalidBoolean(argument: "all_day", value: "yes")))
    }

    @Test("A reminder needs a title, and its due date must parse")
    func reminderRules() throws {
        #expect(validate("reminders_create", [:])
            == .rejection(.missingRequiredArgument(tool: "reminders_create", argument: "title")))
        #expect(validate("reminders_create", ["title": ""])
            == .rejection(.emptyValue(argument: "title")))
        #expect(validate("reminders_create", ["title": "Call the vet", "due_date": "next week"])
            == .rejection(.invalidDate(argument: "due_date", value: "next week")))

        let result = validate("reminders_create", ["title": "Call the vet", "due_date": "2026-09-03T17:00:00Z"])
        #expect(result == .proposal(ValidatedToolCall(
            name: "reminders_create",
            action: .createReminder(title: "Call the vet", due: try date("2026-09-03T17:00:00Z"))
        )))
    }

    @Test("A reminder in the past is allowed; an event is not")
    func reminderMayBeInThePast() {
        let result = validate("reminders_create", ["title": "File taxes", "due_date": "2026-04-15T12:00:00Z"])
        #expect(result != .rejection(.eventInThePast))
        if case .rejection(let error) = result { Issue.record("unexpected rejection: \(error)") }
    }

    @Test("respond yields a proposal only, and never an execution")
    func respondIsAProposalNotAnExecution() {
        let result = validate("respond", ["message": "It is 9am."])
        #expect(result == .proposal(ValidatedToolCall(
            name: "respond",
            action: .respond(message: "It is 9am.")
        )))

        // The validator has exactly two outcomes. There is no execution case to
        // reach, here or anywhere else: acting on a proposal is the caller's job,
        // after the user confirms it.
        guard case .proposal(let call) = result else {
            Issue.record("expected a proposal")
            return
        }
        #expect(!call.isWrite)

        #expect(validate("respond", ["message": "  "]) == .rejection(.emptyValue(argument: "message")))
    }

    @Test("Parser and validator compose over a full model output")
    func endToEnd() throws {
        let raw = try ToolCallParser.parse(
            #"[{"name":"calendar_create_event","arguments":{"title":"Lunch with Sam","start_date":"2026-09-01T12:00:00-04:00"}}]"#
        )
        guard case .proposal(let call) = validator.validate(raw) else {
            Issue.record("expected a proposal")
            return
        }
        #expect(call.action == .createEvent(
            title: "Lunch with Sam",
            start: try date("2026-09-01T16:00:00Z"),
            end: nil,
            isAllDay: false
        ))
    }
}
