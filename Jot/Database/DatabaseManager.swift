import Foundation
import GRDB

final class DatabaseManager {
    static let shared = try! DatabaseManager()

    let dbQueue: DatabaseQueue
    let databaseURL: URL

    init(databaseURL: URL? = nil, inMemory: Bool = false) throws {
        if inMemory {
            self.databaseURL = URL(fileURLWithPath: "/dev/null")
            self.dbQueue = try DatabaseQueue()
        } else {
            let resolvedURL = databaseURL ?? AppPaths.databaseURL
            self.databaseURL = resolvedURL
            try FileManager.default.createDirectory(at: resolvedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            self.dbQueue = try DatabaseQueue(path: resolvedURL.path)
        }
        try Self.migrator.migrate(dbQueue)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_create_tasks") { db in
            try db.create(table: Task.databaseTableName) { table in
                table.column("id", .text).primaryKey()
                table.column("raw_input", .text).notNull()
                table.column("title", .text).notNull()
                table.column("queue", .text).notNull().defaults(to: TaskQueue.work.rawValue)
                table.column("status", .text).notNull().defaults(to: TaskStatus.active.rawValue)
                table.column("person", .text)
                table.column("due_date", .text)
                table.column("note", .text)
                table.column("done_at", .text)
                table.column("created_at", .text).notNull()
                table.column("position", .integer).notNull()
            }
            try db.create(index: "idx_tasks_queue_status_position", on: Task.databaseTableName, columns: ["queue", "status", "position"])
            try db.create(index: "idx_tasks_due_date", on: Task.databaseTableName, columns: ["due_date"])
        }

        migrator.registerMigration("v2_meeting_inbox") { db in
            try db.create(table: Meeting.databaseTableName) { table in
                table.column("id", .text).primaryKey()
                table.column("title", .text).notNull()
                table.column("attendees", .text)
                table.column("started_at", .text).notNull()
                table.column("ended_at", .text)
            }
            try db.create(index: "idx_meetings_started_at", on: Meeting.databaseTableName, columns: ["started_at"])
            try db.alter(table: Task.databaseTableName) { table in
                table.add(column: "meeting_id", .text)
                table.add(column: "kind", .text).notNull().defaults(to: "task")
            }
        }

        migrator.registerMigration("v3_thought_queue") { db in
            // Promote thoughts from kind='thought' flag to a proper queue value
            try db.execute(
                sql: "UPDATE tasks SET queue = 'thought' WHERE kind = 'thought'"
            )
        }

        migrator.registerMigration("v4_daily_focus_items") { db in
            try db.create(table: DailyFocusItem.databaseTableName) { table in
                table.column("id", .text).primaryKey()
                table.column("day_key", .text).notNull()
                table.column("title", .text).notNull()
                table.column("is_done", .boolean).notNull().defaults(to: false)
                table.column("source_task_id", .text)
                table.column("created_at", .text).notNull()
                table.column("position", .integer).notNull()
            }
            try db.create(index: "idx_daily_focus_day_position", on: DailyFocusItem.databaseTableName, columns: ["day_key", "position"])
            try db.create(index: "idx_daily_focus_day_done_position", on: DailyFocusItem.databaseTableName, columns: ["day_key", "is_done", "position"])
            try db.create(index: "idx_daily_focus_source_task", on: DailyFocusItem.databaseTableName, columns: ["source_task_id"])
        }

        migrator.registerMigration("v5_task_daily_focus") { db in
            try db.alter(table: Task.databaseTableName) { table in
                table.add(column: "daily_focus_date", .text)
            }
            try db.create(index: "idx_tasks_daily_focus_date", on: Task.databaseTableName, columns: ["daily_focus_date"])
        }

        migrator.registerMigration("v6_meeting_summary") { db in
            try db.alter(table: Meeting.databaseTableName) { table in
                table.add(column: "summary", .text)
            }
        }

        return migrator
    }

    // MARK: - Task CRUD

    @discardableResult
    func createTask(
        rawInput: String,
        title: String,
        queue: TaskQueue,
        person: String? = nil,
        dueDate: Date? = nil,
        note: String? = nil,
        meetingId: String? = nil,
        dailyFocusDate: String? = nil,
        now: Date = .now
    ) throws -> Task {
        var task = Task(
            rawInput: rawInput,
            title: title,
            queue: queue,
            status: .active,
            person: person,
            dueDate: dueDate,
            note: note,
            createdAt: now,
            position: try nextPosition(in: queue),
            meetingId: meetingId,
            dailyFocusDate: dailyFocusDate
        )
        try dbQueue.write { db in
            try task.insert(db)
        }
        notifyChange()
        return task
    }

    func fetchTasks(queue: TaskQueue? = nil, status: TaskStatus? = nil) throws -> [Task] {
        try dbQueue.read { db in
            var request = Task.order(Task.Columns.position.asc, Task.Columns.createdAt.asc)
            if let queue {
                request = request.filter(Task.Columns.queue == queue.rawValue)
            }
            if let status {
                request = request.filter(Task.Columns.status == status.rawValue)
            }
            return try request.fetchAll(db)
        }
    }

    func fetchAllTasks() throws -> [Task] {
        try fetchTasks()
    }

    func fetchTask(id: String) throws -> Task? {
        try dbQueue.read { db in
            try Task.fetchOne(db, key: id)
        }
    }

    func fetchTasksForMeeting(_ meetingId: String) throws -> [Task] {
        try dbQueue.read { db in
            try Task
                .filter(Task.Columns.meetingId == meetingId)
                .order(Task.Columns.createdAt.asc)
                .fetchAll(db)
        }
    }

    func fetchThoughts() throws -> [Task] {
        try dbQueue.read { db in
            try Task
                .filter(Task.Columns.queue == TaskQueue.thought.rawValue)
                .filter(Task.Columns.meetingId == nil)
                .order(Task.Columns.position.asc, Task.Columns.createdAt.asc)
                .fetchAll(db)
        }
    }

    func updateTask(_ task: Task) throws {
        try dbQueue.write { db in
            try task.update(db)
        }
        notifyChange()
    }

    func deleteTask(id: String) throws {
        _ = try dbQueue.write { db in
            try Task.deleteOne(db, key: id)
        }
        notifyChange()
    }

    func toggleDone(id: String, now: Date = .now) throws {
        try dbQueue.write { db in
            guard var task = try Task.fetchOne(db, key: id) else { return }
            switch task.status {
            case .active:
                task.status = .done
                task.doneAt = DateCodec.string(from: now)
            case .done, .archived:
                task.status = .active
                task.doneAt = nil
            }
            try task.update(db)
        }
        notifyChange()
    }

    func reorderTask(queue: TaskQueue, orderedIDs: [String]) throws {
        try dbQueue.write { db in
            for (index, id) in orderedIDs.enumerated() {
                try db.execute(
                    sql: "UPDATE tasks SET position = ? WHERE id = ? AND queue = ?",
                    arguments: [index, id, queue.rawValue]
                )
            }
        }
        notifyChange()
    }

    @discardableResult
    func archiveOldTasks(now: Date = .now) throws -> Int {
        let cutoff = DateCodec.string(from: now.addingTimeInterval(-24 * 60 * 60))
        let archived = try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE tasks SET status = ? WHERE status = ? AND done_at IS NOT NULL AND done_at <= ?",
                arguments: [TaskStatus.archived.rawValue, TaskStatus.done.rawValue, cutoff]
            )
            return db.changesCount
        }
        if archived > 0 { notifyChange() }
        return Int(archived)
    }

    func dueTodayTasks(limit: Int = 5, now: Date = .now, calendar: Calendar = .current) throws -> [Task] {
        let startOfDay = calendar.startOfDay(for: now)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return [] }
        let start = DateCodec.string(from: startOfDay)
        let end = DateCodec.string(from: endOfDay)
        return try dbQueue.read { db in
            try Task
                .filter(Task.Columns.status == TaskStatus.active.rawValue)
                .filter(Task.Columns.dueDate >= start && Task.Columns.dueDate < end)
                .order(Task.Columns.dueDate.asc, Task.Columns.position.asc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func dueTodayCount(now: Date = .now, calendar: Calendar = .current) throws -> Int {
        try dueTodayTasks(limit: Int.max, now: now, calendar: calendar).count
    }

    func snoozeTask(id: String, days: Int, now: Date = .now, calendar: Calendar = .current) throws {
        try dbQueue.write { db in
            guard var task = try Task.fetchOne(db, key: id) else { return }
            let baseDate = task.dueDateValue ?? now
            guard let snoozed = calendar.date(byAdding: .day, value: days, to: baseDate) else { return }
            task.dueDate = DateCodec.string(from: snoozed)
            try task.update(db)
        }
        notifyChange()
    }

    func markTaskDone(id: String, now: Date = .now) throws {
        try dbQueue.write { db in
            guard var task = try Task.fetchOne(db, key: id) else { return }
            task.status = .done
            task.doneAt = DateCodec.string(from: now)
            try task.update(db)
        }
        notifyChange()
    }

    func resurfaceOverdueReachOuts(now: Date = .now, calendar: Calendar = .current) throws {
        let nowString = DateCodec.string(from: now)
        let tasks = try dbQueue.read { db in
            try Task
                .filter(Task.Columns.queue == TaskQueue.reachOut.rawValue)
                .filter(Task.Columns.status == TaskStatus.active.rawValue)
                .filter(Task.Columns.dueDate != nil)
                .filter(Task.Columns.dueDate < nowString)
                .fetchAll(db)
        }
        guard !tasks.isEmpty else { return }
        try dbQueue.write { db in
            for var task in tasks {
                let from = task.dueDateValue ?? now
                guard let next = calendar.date(byAdding: .day, value: 7, to: from) else { continue }
                task.dueDate = DateCodec.string(from: next)
                try task.update(db)
            }
        }
        notifyChange()
    }

    func deleteTasks(ids: Set<String>) throws {
        guard !ids.isEmpty else { return }
        try dbQueue.write { db in
            for id in ids { try Task.deleteOne(db, key: id) }
        }
        notifyChange()
    }

    func markTasksDone(ids: Set<String>, now: Date = .now) throws {
        guard !ids.isEmpty else { return }
        let doneAt = DateCodec.string(from: now)
        try dbQueue.write { db in
            for id in ids {
                guard var task = try Task.fetchOne(db, key: id) else { continue }
                task.status = .done
                task.doneAt = doneAt
                try task.update(db)
            }
        }
        notifyChange()
    }

    func snoozeTasks(ids: Set<String>, days: Int, now: Date = .now, calendar: Calendar = .current) throws {
        guard !ids.isEmpty else { return }
        try dbQueue.write { db in
            for id in ids {
                guard var task = try Task.fetchOne(db, key: id) else { continue }
                let baseDate = task.dueDateValue ?? now
                guard let snoozed = calendar.date(byAdding: .day, value: days, to: baseDate) else { continue }
                task.dueDate = DateCodec.string(from: snoozed)
                try task.update(db)
            }
        }
        notifyChange()
    }

    func resetAllData() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM tasks")
            try db.execute(sql: "DELETE FROM meetings")
            try db.execute(sql: "DELETE FROM daily_focus_items")
        }
        notifyChange()
    }

    // MARK: - Meeting CRUD

    @discardableResult
    func createMeeting(title: String, attendees: String? = nil, summary: String? = nil, now: Date = .now) throws -> Meeting {
        var meeting = Meeting(title: title, attendees: attendees, summary: summary, startedAt: now)
        try dbQueue.write { db in try meeting.insert(db) }
        notifyChange()
        return meeting
    }

    func fetchMeetings() throws -> [Meeting] {
        try dbQueue.read { db in
            try Meeting.order(Meeting.Columns.startedAt.desc).fetchAll(db)
        }
    }

    func fetchActiveMeeting() throws -> Meeting? {
        try dbQueue.read { db in
            try Meeting
                .filter(Meeting.Columns.endedAt == nil)
                .order(Meeting.Columns.startedAt.desc)
                .fetchOne(db)
        }
    }

    func endMeeting(id: String, summary: String? = nil, now: Date = .now) throws {
        try dbQueue.write { db in
            guard var meeting = try Meeting.fetchOne(db, key: id) else { return }
            if let summary {
                meeting.summary = summary
            }
            meeting.endedAt = DateCodec.string(from: now)
            try meeting.update(db)
        }
        notifyChange()
    }

    func deleteMeeting(id: String) throws {
        try dbQueue.write { db in
            try Meeting.deleteOne(db, key: id)
            try db.execute(sql: "UPDATE tasks SET meeting_id = NULL WHERE meeting_id = ?", arguments: [id])
        }
        notifyChange()
    }

    func updateMeeting(_ meeting: Meeting) throws {
        try dbQueue.write { db in try meeting.update(db) }
        notifyChange()
    }

    // MARK: - Daily Focus

    @discardableResult
    func createDailyFocusItem(
        title: String,
        sourceTaskId: String? = nil,
        dayKey: String = DatabaseManager.dayKey(for: .now),
        now: Date = .now
    ) throws -> DailyFocusItem {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(domain: "Jot.Database", code: 1, userInfo: [NSLocalizedDescriptionKey: "Daily focus title cannot be empty"])
        }

        var item = DailyFocusItem(
            dayKey: dayKey,
            title: trimmed,
            isDone: false,
            sourceTaskId: sourceTaskId,
            createdAt: now,
            position: try nextDailyFocusPosition(dayKey: dayKey)
        )

        try dbQueue.write { db in
            try item.insert(db)
        }
        notifyChange()
        return item
    }

    @discardableResult
    func createDailyFocusItem(from task: Task, dayKey: String = DatabaseManager.dayKey(for: .now), now: Date = .now) throws -> DailyFocusItem {
        if let existing = try fetchDailyFocusItem(sourceTaskId: task.id, dayKey: dayKey) {
            return existing
        }
        return try createDailyFocusItem(title: task.title, sourceTaskId: task.id, dayKey: dayKey, now: now)
    }

    func fetchDailyFocusItems(dayKey: String = DatabaseManager.dayKey(for: .now)) throws -> [DailyFocusItem] {
        try dbQueue.read { db in
            try DailyFocusItem
                .filter(DailyFocusItem.Columns.dayKey == dayKey)
                .order(DailyFocusItem.Columns.isDone.asc, DailyFocusItem.Columns.position.asc, DailyFocusItem.Columns.createdAt.asc)
                .fetchAll(db)
        }
    }

    func updateDailyFocusItem(_ item: DailyFocusItem) throws {
        try dbQueue.write { db in
            try item.update(db)
        }
        notifyChange()
    }

    func toggleDailyFocusDone(id: String) throws {
        try dbQueue.write { db in
            guard var item = try DailyFocusItem.fetchOne(db, key: id) else { return }
            item.isDone.toggle()
            try item.update(db)
        }
        notifyChange()
    }

    func deleteDailyFocusItem(id: String) throws {
        _ = try dbQueue.write { db in
            try DailyFocusItem.deleteOne(db, key: id)
        }
        notifyChange()
    }

    func reorderDailyFocus(dayKey: String = DatabaseManager.dayKey(for: .now), orderedIDs: [String]) throws {
        try dbQueue.write { db in
            for (index, id) in orderedIDs.enumerated() {
                try db.execute(
                    sql: "UPDATE daily_focus_items SET position = ? WHERE id = ? AND day_key = ?",
                    arguments: [index, id, dayKey]
                )
            }
        }
        notifyChange()
    }

    // MARK: - Task Daily Focus

    func setTaskDailyFocus(id: String, dayKey: String = DatabaseManager.dayKey(for: .now)) throws {
        try dbQueue.write { db in
            guard var task = try Task.fetchOne(db, key: id) else { return }
            task.dailyFocusDate = dayKey
            try task.update(db)
        }
        notifyChange()
    }

    func removeTaskDailyFocus(id: String) throws {
        try dbQueue.write { db in
            guard var task = try Task.fetchOne(db, key: id) else { return }
            task.dailyFocusDate = nil
            try task.update(db)
        }
        notifyChange()
    }

    func fetchDailyFocusTasks(dayKey: String = DatabaseManager.dayKey(for: .now)) throws -> [Task] {
        try dbQueue.read { db in
            try Task
                .filter(Task.Columns.dailyFocusDate == dayKey)
                .order(Task.Columns.status.asc, Task.Columns.position.asc, Task.Columns.createdAt.asc)
                .fetchAll(db)
        }
    }

    // MARK: - Private

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let day = calendar.startOfDay(for: date)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: day)
    }

    private func nextPosition(in queue: TaskQueue) throws -> Int64 {
        try dbQueue.read { db in
            let max: Int64? = try Int64.fetchOne(
                db,
                sql: "SELECT MAX(position) FROM tasks WHERE queue = ?",
                arguments: [queue.rawValue]
            )
            return (max ?? -1) + 1
        }
    }

    private func nextDailyFocusPosition(dayKey: String) throws -> Int64 {
        try dbQueue.read { db in
            let max: Int64? = try Int64.fetchOne(
                db,
                sql: "SELECT MAX(position) FROM daily_focus_items WHERE day_key = ?",
                arguments: [dayKey]
            )
            return (max ?? -1) + 1
        }
    }

    private func fetchDailyFocusItem(sourceTaskId: String, dayKey: String) throws -> DailyFocusItem? {
        try dbQueue.read { db in
            try DailyFocusItem
                .filter(DailyFocusItem.Columns.sourceTaskId == sourceTaskId)
                .filter(DailyFocusItem.Columns.dayKey == dayKey)
                .fetchOne(db)
        }
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: .jotDatabaseDidChange, object: nil)
    }
}
