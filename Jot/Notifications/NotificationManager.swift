import Foundation
import UserNotifications

protocol UserNotificationCenterType: AnyObject {
    var delegate: UNUserNotificationCenterDelegate? { get set }
    func requestAuthorization(options: UNAuthorizationOptions, completionHandler: @escaping @Sendable (Bool, Error?) -> Void)
    func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)?)
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
}

extension UNUserNotificationCenter: UserNotificationCenterType {}

@MainActor
final class NotificationManager: NSObject {
    static let categoryIdentifier = "JOT_REACH_OUT"
    static let actionDoneIdentifier = "JOT_DONE"
    static let actionSnoozeIdentifier = "JOT_SNOOZE"

    private enum RequestID {
        static let morningSummary = "jot.morning.summary"
        static let dueTaskPrefix = "jot.task.due."
    }

    private enum DefaultKey {
        static let scheduledDueNotificationIDs = "scheduledDueNotificationIDs"
    }

    private let center: (any UserNotificationCenterType)?
    private let database: DatabaseManager
    private let settings: SettingsStore
    private let defaults: UserDefaults
    private var timer: Timer?
    private var settingsObserver: NSObjectProtocol?
    private var databaseObserver: NSObjectProtocol?

    init(
        database: DatabaseManager,
        settings: SettingsStore,
        center: (any UserNotificationCenterType)? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.center = center ?? Self.makeNotificationCenterIfAvailable()
        self.database = database
        self.settings = settings
        self.defaults = defaults
        super.init()

        if let center = self.center {
            center.delegate = self
            configureActions()
        }

        settingsObserver = NotificationCenter.default.addObserver(
            forName: .jotSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            _Concurrency.Task { @MainActor [weak self] in
                self?.refreshScheduledNotifications()
            }
        }

        databaseObserver = NotificationCenter.default.addObserver(
            forName: .jotDatabaseDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            _Concurrency.Task { @MainActor [weak self] in
                self?.refreshScheduledNotifications()
            }
        }
    }

    deinit {
        timer?.invalidate()
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
        if let databaseObserver {
            NotificationCenter.default.removeObserver(databaseObserver)
        }
    }

    func bootstrap() {
        requestAuthorizationIfNeeded()
        refreshScheduledNotifications()
        startMaintenanceTimer()
    }

    func requestAuthorizationIfNeeded() {
        guard let center else { return }
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func scheduleMorningSummary() {
        guard let center else { return }
        center.removePendingNotificationRequests(withIdentifiers: [RequestID.morningSummary])
        guard settings.notificationsEnabled, settings.summaryEnabled else { return }

        var components = DateComponents()
        components.hour = settings.summaryHour
        components.minute = settings.summaryMinute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let content = UNMutableNotificationContent()
        content.title = "Jot Summary"
        content.body = "Open Jot to review what is due today."
        content.sound = nil
        content.badge = 0

        let request = UNNotificationRequest(identifier: RequestID.morningSummary, content: content, trigger: trigger)
        center.add(request, withCompletionHandler: nil)
    }

    func scheduleDueNotifications(now: Date = .now, calendar: Calendar = .current) {
        guard let center else { return }

        let existingIDs = scheduledDueNotificationIDs()
        if !existingIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: existingIDs)
            center.removeDeliveredNotifications(withIdentifiers: existingIDs)
        }

        guard settings.notificationsEnabled else {
            setScheduledDueNotificationIDs([])
            return
        }

        guard let tasks = try? database.fetchAllTasks() else {
            setScheduledDueNotificationIDs([])
            return
        }

        let scheduledIDs = tasks
            .filter { $0.status == .active && $0.queue != .thought }
            .sorted { ($0.dueDateValue ?? .distantFuture) < ($1.dueDateValue ?? .distantFuture) }
            .compactMap { task -> String? in
                guard let due = task.dueDateValue, due > now else { return nil }

                let identifier = Self.dueNotificationIdentifier(for: task.id)
                let content = UNMutableNotificationContent()
                content.title = task.queue == .reachOut ? "Follow-Up Due" : "Task Due"
                content.subtitle = TaskDueFormatter.detailLabel(for: due, now: now, calendar: calendar)
                content.body = task.title
                content.categoryIdentifier = Self.categoryIdentifier
                content.sound = .default
                content.badge = 0

                var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: due)
                components.second = 0
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                center.add(request, withCompletionHandler: nil)
                return identifier
            }

        setScheduledDueNotificationIDs(scheduledIDs)
    }

    func startMaintenanceTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.tick()
            }
        }
        tick()
    }

    func tick(now: Date = .now) {
        scheduleMorningSummary()
        try? database.resurfaceOverdueReachOuts(now: now)
        _ = try? database.archiveOldTasks(now: now)
    }

    private func refreshScheduledNotifications(now: Date = .now) {
        scheduleMorningSummary()
        scheduleDueNotifications(now: now)
    }

    private func configureActions() {
        guard let center else { return }
        let done = UNNotificationAction(identifier: Self.actionDoneIdentifier, title: "Done", options: [])
        let snooze = UNNotificationAction(identifier: Self.actionSnoozeIdentifier, title: "Snooze", options: [])
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [done, snooze],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    private static func dueNotificationIdentifier(for taskID: String) -> String {
        RequestID.dueTaskPrefix + taskID
    }

    private func scheduledDueNotificationIDs() -> [String] {
        defaults.array(forKey: DefaultKey.scheduledDueNotificationIDs) as? [String] ?? []
    }

    private func setScheduledDueNotificationIDs(_ identifiers: [String]) {
        defaults.set(identifiers, forKey: DefaultKey.scheduledDueNotificationIDs)
    }

    private static func makeNotificationCenterIfAvailable() -> (any UserNotificationCenterType)? {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return nil
        }
        return UNUserNotificationCenter.current()
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        let actionIdentifier = response.actionIdentifier
        let taskID = identifier.hasPrefix(RequestID.dueTaskPrefix)
            ? String(identifier.dropFirst(RequestID.dueTaskPrefix.count))
            : nil

        if let taskID {
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    completionHandler()
                    return
                }
                switch actionIdentifier {
                case Self.actionDoneIdentifier:
                    try? self.database.markTaskDone(id: taskID)
                case Self.actionSnoozeIdentifier:
                    try? self.database.snoozeTask(id: taskID, days: self.settings.snoozeDays)
                default:
                    break
                }
                completionHandler()
            }
        } else {
            completionHandler()
        }
    }
}
