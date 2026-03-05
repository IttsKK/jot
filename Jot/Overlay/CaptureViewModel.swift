import Foundation

@MainActor
final class CaptureViewModel: ObservableObject {
    @Published var input: String = ""
    @Published var focusNonce: UUID = UUID()
    @Published private(set) var parsed: ParsedTask = ParsedTask(rawInput: "", title: "", type: .task, queue: .work, person: nil, dueDate: nil, note: nil)
    @Published private(set) var forcedKind: ItemKind? = nil
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
        // Consume mode-setting prefixes immediately when the full token is written (prefix + space)
        if consumeNextPrefix() { return }

        if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            forcedKind = nil
            forcedQueue = nil
            parsed = ParsedTask(rawInput: "", title: "", type: .task, queue: settings.defaultQueue, person: nil, dueDate: nil, note: nil)
            return
        }

        parsed = TaskParser.parse(input)

        // Overlay forced modes onto parse result
        if forcedKind == .thought {
            parsed.type = .thought
        }
        if let q = forcedQueue {
            parsed.queue = q
        }
    }

    /// Strips a single mode prefix from `input` and records the mode. Returns `true` if a prefix was consumed
    /// (caller should return early — updateParse will be triggered again by the input change).
    @discardableResult
    private func consumeNextPrefix() -> Bool {
        let prefixes: [(String, () -> Void)] = [
            ("/t ", { self.forcedKind = .thought; self.forcedQueue = nil }),
            ("// ", { self.forcedKind = .thought; self.forcedQueue = nil }),
            ("/w ", { self.forcedQueue = .work }),
            ("/r ", { self.forcedQueue = .reachOut }),
        ]
        for (prefix, apply) in prefixes {
            if input.hasPrefix(prefix) {
                input = String(input.dropFirst(prefix.count))
                apply()
                return true
            }
        }
        return false
    }

    func save() throws {
        let raw = parsed.title.isEmpty ? TaskParser.parse(input) : parsed
        var effective = raw
        if forcedKind == .thought { effective.type = .thought }
        if let q = forcedQueue { effective.queue = q }

        let title = TaskTextFormatter.formattedTitle(effective.title)
        guard !title.isEmpty else { return }

        let isThought = effective.type == .thought
        let kind: ItemKind = isThought ? .thought : .task
        let meetingId = meetingSession.activeMeeting?.id

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
        forcedKind = nil
        forcedQueue = nil
        parsed = ParsedTask(rawInput: "", title: "", type: .task, queue: settings.defaultQueue, person: nil, dueDate: nil, note: nil)
    }

    func requestFocus() {
        focusNonce = UUID()
    }
}

