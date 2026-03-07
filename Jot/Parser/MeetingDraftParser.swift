import Foundation

struct MeetingDraft: Equatable, Sendable {
    let title: String
    let person: String?
}

enum MeetingDraftParser {
    static func parse(_ input: String) -> MeetingDraft {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return MeetingDraft(title: "", person: nil)
        }

        let lower = trimmed.lowercased()
        if let range = lower.range(of: " with "), range.lowerBound != lower.startIndex {
            let title = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let person = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return MeetingDraft(
                title: TaskTextFormatter.formattedTitle(title),
                person: TaskTextFormatter.formattedPerson(person)
            )
        }

        return MeetingDraft(
            title: TaskTextFormatter.formattedTitle(trimmed),
            person: nil
        )
    }
}
