#if canImport(XCTest)
import XCTest
@testable import Jot

final class DatabaseManagerTests: XCTestCase {
    private var db: DatabaseManager!
    private var calendar: Calendar!

    override func setUpWithError() throws {
        calendar = Calendar(identifier: .gregorian)
        db = try DatabaseManager(inMemory: true)
    }

    func testCreateFetchUpdateDeleteFlow() throws {
        let created = try db.createTask(rawInput: "write report", title: "write report", queue: .work)
        var tasks = try db.fetchTasks(queue: .work, status: .active)
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.id, created.id)

        var edited = try XCTUnwrap(tasks.first)
        edited.title = "write weekly report"
        try db.updateTask(edited)

        tasks = try db.fetchTasks(queue: .work, status: .active)
        XCTAssertEqual(tasks.first?.title, "write weekly report")

        try db.deleteTask(id: edited.id)
        tasks = try db.fetchTasks(queue: .work, status: .active)
        XCTAssertTrue(tasks.isEmpty)
    }

    func testToggleDoneSetsAndClearsDoneAt() throws {
        let anchor = date(2026, 3, 3, 9, 0)
        let task = try db.createTask(rawInput: "follow up", title: "follow up", queue: .reachOut, now: anchor)

        try db.toggleDone(id: task.id, now: anchor)
        let doneTask = try XCTUnwrap(try db.fetchTasks(queue: .reachOut).first)
        XCTAssertEqual(doneTask.status, .done)
        XCTAssertNotNil(doneTask.doneAt)

        try db.toggleDone(id: task.id, now: anchor)
        let reopened = try XCTUnwrap(try db.fetchTasks(queue: .reachOut).first)
        XCTAssertEqual(reopened.status, .active)
        XCTAssertNil(reopened.doneAt)
    }

    func testArchiveOldTasksUses24HourRule() throws {
        let anchor = date(2026, 3, 3, 12, 0)
        let oldDoneDate = anchor.addingTimeInterval(-(25 * 60 * 60))
        let recentDoneDate = anchor.addingTimeInterval(-(3 * 60 * 60))

        var oldTask = try db.createTask(rawInput: "old", title: "old", queue: .work, now: anchor)
        oldTask.status = .done
        oldTask.doneAt = DateCodec.string(from: oldDoneDate)
        try db.updateTask(oldTask)

        var recentTask = try db.createTask(rawInput: "recent", title: "recent", queue: .work, now: anchor)
        recentTask.status = .done
        recentTask.doneAt = DateCodec.string(from: recentDoneDate)
        try db.updateTask(recentTask)

        let archivedCount = try db.archiveOldTasks(now: anchor)
        XCTAssertEqual(archivedCount, 1)

        let all = try db.fetchTasks(queue: .work)
        let archived = all.first(where: { $0.id == oldTask.id })
        let recent = all.first(where: { $0.id == recentTask.id })

        XCTAssertEqual(archived?.status, .archived)
        XCTAssertEqual(recent?.status, .done)
    }

    func testReorderPersistsPosition() throws {
        let a = try db.createTask(rawInput: "a", title: "a", queue: .work)
        let b = try db.createTask(rawInput: "b", title: "b", queue: .work)
        let c = try db.createTask(rawInput: "c", title: "c", queue: .work)

        try db.reorderTask(queue: .work, orderedIDs: [c.id, a.id, b.id])
        let tasks = try db.fetchTasks(queue: .work, status: .active)
        XCTAssertEqual(tasks.map(\.id), [c.id, a.id, b.id])
    }

    func testDatabasePathCreationForFileDatabase() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dbURL = root.appendingPathComponent("tasks.db")
        let localDB = try DatabaseManager(databaseURL: dbURL)

        _ = try localDB.createTask(rawInput: "x", title: "x", queue: .work)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbURL.path))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.calendar = calendar
        return components.date!
    }
}
#endif
