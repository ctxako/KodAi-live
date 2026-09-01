import Foundation

/// A syntactically well-formed tool call, before anything is known about
/// whether it means something sensible.
public struct RawToolCall: Equatable, Sendable {
    public let name: String
    public let arguments: [String: String]

    public init(name: String, arguments: [String: String]) {
        self.name = name
        self.arguments = arguments
    }
}

public enum ToolCallParseError: Error, Equatable, Sendable {
    case malformedJSON
    case notAnArray
    case noCalls
    case multipleCalls(Int)
    case missingName
    case missingArguments
    case unsupportedArgumentValue(key: String)
}

/// Parses the one call shape this artifact supports:
///
/// ```json
/// [{ "name": "respond", "arguments": { "message": "Hello" } }]
/// ```
///
/// Even with a grammar attached to the sampler, the parser stays strict. A
/// grammar constrains generation, not the text that reaches this function: a
/// cached completion, a different backend, or a fallback path with sampling
/// unconstrained all arrive here too, and the failure has to be clean rather
/// than a half-populated call.
public enum ToolCallParser {

    public static func parse(_ text: String) throws -> RawToolCall {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data)
        else { throw ToolCallParseError.malformedJSON }

        guard let calls = json as? [Any] else { throw ToolCallParseError.notAnArray }
        guard !calls.isEmpty else { throw ToolCallParseError.noCalls }
        // One call per turn. Two proposals from one utterance is a confirmation
        // problem, not a parsing problem, so it is refused here rather than
        // silently taking the first.
        guard calls.count == 1 else { throw ToolCallParseError.multipleCalls(calls.count) }

        guard let call = calls[0] as? [String: Any] else { throw ToolCallParseError.malformedJSON }
        guard let name = call["name"] as? String, !name.isEmpty else {
            throw ToolCallParseError.missingName
        }
        guard let rawArguments = call["arguments"] as? [String: Any] else {
            throw ToolCallParseError.missingArguments
        }

        var arguments: [String: String] = [:]
        for (key, value) in rawArguments {
            switch value {
            case let string as String:
                arguments[key] = string
            case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
                // JSON booleans are normalized to "true"/"false" so downstream
                // code has exactly one value type to reason about.
                arguments[key] = number.boolValue ? "true" : "false"
            default:
                throw ToolCallParseError.unsupportedArgumentValue(key: key)
            }
        }

        return RawToolCall(name: name, arguments: arguments)
    }
}
