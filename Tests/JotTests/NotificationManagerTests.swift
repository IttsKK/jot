#if canImport(XCTest)
import AppKit
import XCTest
import UserNotifications
@testable import Jot

@MainActor
final class NotificationManagerTests: XCTestCase {
    func testSchedulesDueNotificationsForActiveWorkAndFollowUpTasks() throws {
        _ = NSApplication.shared
        let database = try DatabaseManager(inMemory: true)
        let defaults = makeDefaults()
        let settings = SettingsStore(defaults: defaults)
        let center = FakeNotificationCenter()
        let manager = NotificationManager(database: database, settings: settings, center: center, defaults: defaults)
        let calendar = makeCalendar()
        let now = makeDate(2026, 3, 29, 8, 0, calendar: calendar)

        let workDue = makeDate(2026, 3, 29, 11, 0, calendar: calendar)
        let reachOutDue = makeDate(2026, 3, 30, 10, 0, calendar: calendar)
        let thoughtDue = makeDate(2026, 3, 29, 12, 0, calendar: calendar)
        let doneDue = makeDate(2026, 3, 29, 13, 0, calendar: calendar)

        let workTask = try database.createTask(rawInput: "ship patch", title: "Ship Patch", queue: .work, dueDate: workDue, now: now)
        let reachOutTask = try database.createTask(rawInput: "email maria", title: "Email Maria", queue: .reachOut, dueDate: reachOutDue, now: now)
        _ = try database.createTask(rawInput: "meeting note", title: "Meeting Note", queue: .thought, dueDate: thoughtDue, now: now)
        let doneTask = try database.createTask(rawInput: "wrap report", title: "Wrap Report", queue: .work, dueDate: doneDue, now: now)
        try database.markTaskDone(id: doneTask.id, now: now)

        manager.scheduleDueNotifications(now: now, calendar: calendar)

        let dueIDs = center.addedRequests
            .map(\.identifier)
            .filter { $0.hasPrefix("jot.task.due.") }
            .sorted()

        XCTAssertEqual(dueIDs, [
            "jot.task.due.\(workTask.id)",
            "jot.task.due.\(reachOutTask.id)"
        ].sorted())
        XCTAssertFalse(center.addedRequests.contains { $0.content.body == "Meeting Note" })
        XCTAssertFalse(center.addedRequests.contains { $0.content.body == "Wrap Report" })
    }

    func testDisablingNotificationsClearsPendingDueRequests() throws {
        _ = NSApplication.shared
        let database = try DatabaseManager(inMemory: true)
        let defaults = makeDefaults()
        let settings = SettingsStore(defaults: defaults)
        let center = FakeNotificationCenter()
        let manager = NotificationManager(database: database, settings: settings, center: center, defaults: defaults)
        let calendar = makeCalendar()
        let now = makeDate(2026, 3, 29, 8, 0, calendar: calendar)

        let due = makeDate(2026, 3, 29, 11, 0, calendar: calendar)
        let task = try database.createTask(rawInput: "ship patch", title: "Ship Patch", queue: .work, dueDate: due, now: now)

        manager.scheduleDueNotifications(now: now, calendar: calendar)
        XCTAssertTrue(center.addedRequests.contains { $0.identifier == "jot.task.due.\(task.id)" })

        settings.notificationsEnabled = false
        manager.scheduleDueNotifications(now: now, calendar: calendar)

        XCTAssertTrue(center.removedPendingIdentifiers.contains("jot.task.due.\(task.id)"))
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "NotificationManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Vancouver")!
        return calendar
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, calendar: Calendar) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return components.date!
    }
}

private final class FakeNotificationCenter: UserNotificationCenterType {
    weak var delegate: UNUserNotificationCenterDelegate?
    private(set) var addedRequests: [UNNotificationRequest] = []
    private(set) var removedPendingIdentifiers: [String] = []
    private(set) var removedDeliveredIdentifiers: [String] = []

    func requestAuthorization(options: UNAuthorizationOptions, completionHandler: @escaping @Sendable (Bool, Error?) -> Void) {
        completionHandler(true, nil)
    }

    func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)?) {
        addedRequests.append(request)
        completionHandler?(nil)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedPendingIdentifiers.append(contentsOf: identifiers)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        removedDeliveredIdentifiers.append(contentsOf: identifiers)
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {}
}
#endif
