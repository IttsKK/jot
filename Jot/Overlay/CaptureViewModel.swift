import Foundation

@MainActor
final class CaptureViewModel: ObservableObject {
    @Published var input: String = ""
    @Published var focusNonce: UUID = UUID()
    @Published private(set) var parsed: ParsedTask = ParsedTask(rawInput: "", title: "", type: .task, queue: .work, person: nil, dueDate: nil, note: nil)
    @Published private(set) var forcedQueue: TaskQueue? = nil

    let database: DatabaseManager
    let settings: SettingsStore
    let meetingSession: MeetingSession

    init(database: DatabaseManager, settings: SettingsStore, meetingSession: MeetingSession) {
        self.database = database
        self.settings = settings
        self.meetingSession = meetingSession
    }

    func updateParse() {
        if consumeNextPrefix() { return }

        if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            forcedQueue = nil
            parsed = ParsedTask(rawInput: "", title: "", type: .task, queue: settings.defaultQueue, person: nil, dueDate: nil, note: nil)
            return
        }

        parsed = TaskParser.parse(input)

        if let q = forcedQueue {
            parsed.queue = q
            if q == .thought { parsed.type = .thought }
        }
    }

    /// Strips a single mode prefix and records the forced queue. Returns `true` when consumed
    /// so the caller can bail early — `updateParse` will fire again after `input` changes.
    @discardableResult
    private func consumeNextPrefix() -> Bool {
        let prefixes: [(String, TaskQueue)] = [
            ("/t ",  .thought),
            ("// ",  .thought),
            ("/w ",  .work),
            ("/r ",  .reachOut),
        ]
        for (prefix, queue) in prefixes {
            if input.hasPrefix(prefix) {
                input = String(input.dropFirst(prefix.count))
                forcedQueue = queue
                return true
            }
        }
        return false
    }

    func save() throws {
        let raw = parsed.title.isEmpty ? TaskParser.parse(input) : parsed
        var effective = raw
        if let q = forcedQueue {
            effective.queue = q
            if q == .thought { effective.type = .thought }
        }

        let title = TaskTextFormatter.formattedTitle(effective.title)
        guard !title.isEmpty else { return }

        let meetingId = meetingSession.activeMeeting?.id

        var person = TaskTextFormatter.formattedPerson(effective.person)
        if person == nil && effective.queue == .reachOut && meetingSession.isInMeeting {
            person = meetingSession.meetingAttendeeList.first
        }

        try database.createTask(
            rawInput: input,
            title: title,
            queue: effective.queue,
            person: person,
            dueDate: effective.dueDate,
            note: TaskTextFormatter.formattedNote(effective.note),
            meetingId: meetingId
        )
        clear()
    }

    func clear() {
        input = ""
        forcedQueue = nil
        parsed = ParsedTask(rawInput: "", title: "", type: .task, queue: settings.defaultQueue, person: nil, dueDate: nil, note: nil)
    }

    func requestFocus() {
        focusNonce = UUID()
    }
}
