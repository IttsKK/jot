import Foundation

enum InputCommandKind: Equatable, Sendable {
    case queue(TaskQueue)
    case meetingStart
    case meetingEnd
    case meetingSummary
    case today
}

struct InputCommand: Equatable, Sendable {
    let id: String
    let kind: InputCommandKind
    let trigger: String
    let label: String
    let prompt: String
}

struct ConsumedInputCommand: Equatable, Sendable {
    let command: InputCommand
    let remainder: String
}

enum InputCommandParser {
    private struct Definition {
        let command: InputCommand
        let aliases: Set<String>
    }

    private static let definitions: [Definition] = [
        Definition(
            command: InputCommand(id: "work", kind: .queue(.work), trigger: "/w", label: "Work", prompt: "Type a work task..."),
            aliases: ["/w", "/work", "/task"]
        ),
        Definition(
            command: InputCommand(id: "reach_out", kind: .queue(.reachOut), trigger: "/f", label: "Follow Up", prompt: "Who do you need to follow up with?"),
            aliases: ["/f", "/r", "/follow", "/reach", "/followup", "/follow-up"]
        ),
        Definition(
            command: InputCommand(id: "thought", kind: .queue(.thought), trigger: "/n", label: "Note", prompt: "Type a note..."),
            aliases: ["/n", "/note", "/thought", "//"]
        ),
        Definition(
            command: InputCommand(id: "meeting", kind: .meetingStart, trigger: "/meeting", label: "Meeting", prompt: "Meeting draft, optionally 'with Name'"),
            aliases: ["/m", "/meet", "/meeting"]
        ),
        Definition(
            command: InputCommand(id: "meeting_end", kind: .meetingEnd, trigger: "/end", label: "End Meeting", prompt: "Add an optional summary before ending"),
            aliases: ["/end", "/done", "/finish"]
        ),
        Definition(
            command: InputCommand(id: "meeting_summary", kind: .meetingSummary, trigger: "/summary", label: "Meeting Summary", prompt: "Set the meeting summary"),
            aliases: ["/s", "/summary"]
        ),
        Definition(
            command: InputCommand(id: "today", kind: .today, trigger: "/t", label: "Today", prompt: "Add to Today list"),
            aliases: ["/t", "/today", "/td"]
        )
    ]

    static var allCommands: [InputCommand] {
        definitions.map(\.command)
    }

    static func consumeLeadingCommand(from input: String) -> ConsumedInputCommand? {
        let trimmedLeading = input.drop { $0.isWhitespace }
        guard !trimmedLeading.isEmpty else { return nil }

        let tokenEnd = trimmedLeading.firstIndex(where: \.isWhitespace) ?? trimmedLeading.endIndex
        let token = String(trimmedLeading[..<tokenEnd]).lowercased()

        guard let match = definitions.first(where: { $0.aliases.contains(token) }) else {
            return nil
        }

        let remainder = String(trimmedLeading[tokenEnd...]).trimmingCharacters(in: .whitespaces)
        return ConsumedInputCommand(command: match.command, remainder: remainder)
    }

    static func suggestedCommands(for input: String) -> [InputCommand] {
        let trimmedLeading = input.drop { $0.isWhitespace }
        guard !trimmedLeading.isEmpty else { return [] }
        guard trimmedLeading.first == "/" else { return [] }

        let tokenEnd = trimmedLeading.firstIndex(where: \.isWhitespace) ?? trimmedLeading.endIndex
        let token = String(trimmedLeading[..<tokenEnd]).lowercased()
        if token == "/" {
            return allCommands
        }

        return definitions
            .filter { definition in
                definition.aliases.contains(where: { $0.hasPrefix(token) })
            }
            .map(\.command)
    }

    static func expandedRemainder(for command: InputCommand, remainder: String) -> String {
        let trimmed = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        switch command.kind {
        case .queue(.reachOut):
            let lower = trimmed.lowercased()
            if lower.hasPrefix("follow up") ||
                lower.hasPrefix("follow-up") ||
                lower.hasPrefix("check in") ||
                lower.hasPrefix("check-in") ||
                lower.hasPrefix("reach out") ||
                lower.hasPrefix("email") ||
                lower.hasPrefix("call") ||
                lower.hasPrefix("text") ||
                lower.hasPrefix("ping") ||
                lower.hasPrefix("contact") ||
                lower.hasPrefix("message") {
                return trimmed
            }
            if lower.hasPrefix("with ") {
                return "follow up \(trimmed)"
            }
            return "follow up with \(trimmed)"
        default:
            return trimmed
        }
    }
}
