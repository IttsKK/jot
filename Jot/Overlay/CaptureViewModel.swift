import Foundation

@MainActor
final class CaptureViewModel: ObservableObject {
    @Published var input: String = ""
    @Published var focusNonce: UUID = UUID()
    @Published private(set) var parsed: ParsedTask = ParsedTask(rawInput: "", title: "", type: .task, queue: .work, person: nil, dueDate: nil, note: nil)

    let database: DatabaseManager
    let settings: SettingsStore
    let meetingSession: MeetingSession

    init(database: DatabaseManager, settings: SettingsStore, meetingSession: MeetingSession) {
        self.database = database
        self.settings = settings
        self.meetingSession = meetingSession
    }

    func updateParse() {
        parsed = TaskParser.parse(input)
        if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parsed.queue = settings.defaultQueue
        }
    }

    func save() throws {
        let effective = parsed.title.isEmpty ? TaskParser.parse(input) : parsed
        let title = TaskTextFormatter.formattedTitle(effective.title)
        guard !title.isEmpty else { return }

        let isThought = effective.type == .thought
        let kind: ItemKind = isThought ? .thought : .task
        let meetingId = meetingSession.activeMeeting?.id

        // In a meeting: if no person extracted for a follow-up, try to use the first attendee
        var person = TaskTextFormatter.formattedPerson(effective.person)
        if person == nil && effective.queue == .reachOut && meetingSession.isInMeeting {
            person = meetingSession.meetingAttendeeList.first
        }

        try database.createTask(
            rawInput: input,
            title: title,
            queue: isThought ? .work : effective.queue,
            person: person,
            dueDate: effective.dueDate,
            note: TaskTextFormatter.formattedNote(effective.note),
            meetingId: meetingId,
            kind: kind
        )
        clear()
    }

    func clear() {
        input = ""
        parsed = ParsedTask(rawInput: "", title: "", type: .task, queue: settings.defaultQueue, person: nil, dueDate: nil, note: nil)
    }

    func requestFocus() {
        focusNonce = UUID()
    }
}
