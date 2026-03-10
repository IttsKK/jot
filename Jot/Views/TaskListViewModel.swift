import Foundation

@MainActor
final class TaskListViewModel: ObservableObject {
    enum SidebarItem: Hashable {
        case all
        case work
        case followUp
        case inbox
        case meeting(String)
    }

    @Published var selectedItem: SidebarItem = .all
    @Published var tasks: [Task] = []
    @Published var meetings: [Meeting] = []
    @Published var thoughts: [Task] = []
    @Published var selectedTaskIDs: Set<String> = []

    var selectedTasks: [Task] { visibleTasks.filter { selectedTaskIDs.contains($0.id) } }
    var hasSelection: Bool { !selectedTaskIDs.isEmpty }
    var isMultiSelect: Bool { selectedTaskIDs.count > 1 }

    func clearSelection() { selectedTaskIDs.removeAll() }

    func selectAll() { selectedTaskIDs = Set(activeTasks.map(\.id)) }

    func validateSelection() {
        selectedTaskIDs = selectedTaskIDs.intersection(Set(visibleTasks.map(\.id)))
    }

    func moveSelectionUp() {
        let list = activeTasks
        guard !list.isEmpty else { return }
        if selectedTaskIDs.isEmpty { selectedTaskIDs = [list.last!.id]; return }
        guard selectedTaskIDs.count == 1, let id = selectedTaskIDs.first,
              let index = list.firstIndex(where: { $0.id == id }), index > 0 else { return }
        selectedTaskIDs = [list[index - 1].id]
    }

    func moveSelectionDown() {
        let list = activeTasks
        guard !list.isEmpty else { return }
        if selectedTaskIDs.isEmpty { selectedTaskIDs = [list.first!.id]; return }
        guard selectedTaskIDs.count == 1, let id = selectedTaskIDs.first,
              let index = list.firstIndex(where: { $0.id == id }), index < list.count - 1 else { return }
        selectedTaskIDs = [list[index + 1].id]
    }

    private let database: DatabaseManager
    private var observer: NSObjectProtocol?

    init(database: DatabaseManager) {
        self.database = database
        observer = NotificationCenter.default.addObserver(forName: .jotDatabaseDidChange, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async { try? self?.refresh() }
        }
        try? refresh()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func refresh() throws {
        tasks = try database.fetchAllTasks()
        meetings = try database.fetchMeetings()
        thoughts = try database.fetchThoughts()
    }

    var visibleTasks: [Task] {
        switch selectedItem {
        case .all:      return tasks.filter { $0.queue == .work || $0.queue == .reachOut }
        case .work:     return tasks.filter { $0.queue == .work }
        case .followUp: return tasks.filter { $0.queue == .reachOut }
        case .inbox:    return []
        case .meeting:
            guard let meeting = selectedMeeting else { return [] }
            return tasksForMeeting(meeting)
        }
    }

    var activeTasks: [Task] { visibleTasks.filter { $0.status == .active } }

    var completedTasks: [Task] {
        let now = Date()
        return visibleTasks.filter {
            guard $0.status == .done, let doneAt = $0.doneAtValue else { return false }
            return now.timeIntervalSince(doneAt) < 24 * 60 * 60
        }
    }

    var archivedTasks: [Task] { visibleTasks.filter { $0.status == .archived } }

    var selectedMeeting: Meeting? {
        guard case .meeting(let id) = selectedItem else { return nil }
        return meetings.first(where: { $0.id == id })
    }

    func tasksForMeeting(_ meeting: Meeting) -> [Task] {
        tasks.filter { $0.meetingId == meeting.id }
            .sorted { ($0.createdAtValue ?? .distantPast) < ($1.createdAtValue ?? .distantPast) }
    }

    func toggleDone(_ task: Task) { try? database.toggleDone(id: task.id) }
    func delete(_ task: Task) { try? database.deleteTask(id: task.id) }
    func snooze(_ task: Task, days: Int = 7) { try? database.snoozeTask(id: task.id, days: days) }

    func bulkMarkDone() { try? database.markTasksDone(ids: selectedTaskIDs); clearSelection() }
    func bulkDelete() { try? database.deleteTasks(ids: selectedTaskIDs); clearSelection() }
    func bulkSnooze(days: Int = 7) { try? database.snoozeTasks(ids: selectedTaskIDs, days: days); clearSelection() }

    func saveEdits(_ edited: Task) { try? database.updateTask(edited) }
    func deleteMeeting(_ meeting: Meeting) { try? database.deleteMeeting(id: meeting.id) }
    func updateMeetingSummary(_ meeting: Meeting, summary: String?) {
        var edited = meeting
        edited.summary = summary
        try? database.updateMeeting(edited)
    }
    func addTaskToDailyFocus(_ task: Task) { try? database.setTaskDailyFocus(id: task.id) }

    func createTask(rawInput: String, title: String, queue: TaskQueue, person: String?, dueDate: Date?, note: String?, meetingId: String? = nil, dailyFocusDate: String? = nil) {
        _ = try? database.createTask(rawInput: rawInput, title: title, queue: queue, person: person, dueDate: dueDate, note: note, meetingId: meetingId, dailyFocusDate: dailyFocusDate)
    }

    func captureMeetingNote(rawInput: String, content: String, meetingId: String) {
        _ = try? database.captureMeetingNote(rawInput: rawInput, content: content, meetingId: meetingId)
    }

    func updateTask(id: String, rawInput: String, title: String, queue: TaskQueue, status: TaskStatus, person: String?, dueDate: Date?, note: String?) {
        guard var task = tasks.first(where: { $0.id == id }) else { return }
        task.rawInput = rawInput
        task.title = title
        task.queue = queue
        task.status = status
        task.person = person
        task.dueDate = dueDate.map(DateCodec.string(from:))
        task.note = note
        if status != .done { task.doneAt = nil } else if task.doneAt == nil { task.doneAt = DateCodec.string(from: .now) }
        try? database.updateTask(task)
    }

    func moveActive(from source: IndexSet, to destination: Int) {
        var active = activeTasks
        guard let sourceIndex = source.first, sourceIndex < active.count else { return }
        let movedQueue = active[sourceIndex].queue
        active.move(fromOffsets: source, toOffset: destination)
        let orderedIDs = active.filter { $0.queue == movedQueue }.map(\.id)
        try? database.reorderTask(queue: movedQueue, orderedIDs: orderedIDs)
        try? refresh()
    }

    func moveTask(id: String, before targetID: String?) {
        let active = activeTasks
        guard let movingTask = active.first(where: { $0.id == id }) else { return }
        var reordered = active.filter { $0.queue == movingTask.queue && $0.id != id }
        if let targetID, let targetIndex = reordered.firstIndex(where: { $0.id == targetID }) {
            reordered.insert(movingTask, at: targetIndex)
        } else {
            reordered.append(movingTask)
        }
        try? database.reorderTask(queue: movingTask.queue, orderedIDs: reordered.map(\.id))
        try? refresh()
    }

    func moveThought(from source: IndexSet, to destination: Int) {
        var mutableThoughts = thoughts
        mutableThoughts.move(fromOffsets: source, toOffset: destination)
        let orderedIDs = mutableThoughts.map(\.id)
        try? database.reorderTask(queue: .thought, orderedIDs: orderedIDs)
        try? refresh()
    }
}
