#if canImport(XCTest)
import XCTest
@testable import Jot

@MainActor
final class TaskListViewModelTests: XCTestCase {
    func testRecentlyCompletedTaskStaysVisibleDuringUndoWindow() throws {
        let now = makeDate(2026, 3, 18, 9, 0, 4)
        let completedAt = makeDate(2026, 3, 18, 9, 0, 0)
        let database = try DatabaseManager(inMemory: true)
        let task = try database.createTask(rawInput: "ship patch", title: "ship patch", queue: .work, now: completedAt)
        try database.markTaskDone(id: task.id, now: completedAt)

        let viewModel = TaskListViewModel(
            database: database,
            nowProvider: { now },
            completionUndoWindow: 8
        )

        XCTAssertEqual(viewModel.recentlyCompletedTasks.map(\.id), [task.id])
        XCTAssertTrue(viewModel.completedTasks.isEmpty)
        XCTAssertEqual(viewModel.totalCompletedCount, 1)
    }

    func testCompletedTaskMovesBehindCompletedToggleAfterUndoWindow() throws {
        let now = makeDate(2026, 3, 18, 9, 0, 12)
        let completedAt = makeDate(2026, 3, 18, 9, 0, 0)
        let database = try DatabaseManager(inMemory: true)
        let task = try database.createTask(rawInput: "ship patch", title: "ship patch", queue: .work, now: completedAt)
        try database.markTaskDone(id: task.id, now: completedAt)

        let viewModel = TaskListViewModel(
            database: database,
            nowProvider: { now },
            completionUndoWindow: 8
        )

        XCTAssertTrue(viewModel.recentlyCompletedTasks.isEmpty)
        XCTAssertEqual(viewModel.completedTasks.map(\.id), [task.id])
        XCTAssertEqual(viewModel.totalCompletedCount, 1)
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return components.date!
    }
}
#endif
