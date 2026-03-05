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
            meetingId: meetingId
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
                .order(Task.Columns.createdAt.desc)
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
        }
        notifyChange()
    }

    // MARK: - Meeting CRUD

    @discardableResult
    func createMeeting(title: String, attendees: String? = nil, now: Date = .now) throws -> Meeting {
        var meeting = Meeting(title: title, attendees: attendees, startedAt: now)
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

    func endMeeting(id: String, now: Date = .now) throws {
        try dbQueue.write { db in
            guard var meeting = try Meeting.fetchOne(db, key: id) else { return }
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

    // MARK: - Private

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

    private func notifyChange() {
        NotificationCenter.default.post(name: .jotDatabaseDidChange, object: nil)
    }
}
