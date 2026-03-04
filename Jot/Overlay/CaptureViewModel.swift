import Foundation

@MainActor
final class CaptureViewModel: ObservableObject {
    @Published var input: String = ""
    @Published var focusNonce: UUID = UUID()
    @Published private(set) var parsed: ParsedTask = ParsedTask(rawInput: "", title: "", type: .task, queue: .work, person: nil, dueDate: nil, note: nil)

    let database: DatabaseManager
    let settings: SettingsStore

    init(database: DatabaseManager, settings: SettingsStore) {
        self.database = database
        self.settings = settings
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

        try database.createTask(
            rawInput: input,
            title: title,
            queue: effective.queue,
            person: TaskTextFormatter.formattedPerson(effective.person),
            dueDate: effective.dueDate,
            note: TaskTextFormatter.formattedNote(effective.note)
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
