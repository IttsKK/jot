import Foundation
import UserNotifications

@MainActor
final class NotificationManager: NSObject {
    static let categoryIdentifier = "JOT_REACH_OUT"
    static let actionDoneIdentifier = "JOT_DONE"
    static let actionSnoozeIdentifier = "JOT_SNOOZE"

    private let center: UNUserNotificationCenter?
    private let database: DatabaseManager
    private let settings: SettingsStore
    private var timer: Timer?

    init(database: DatabaseManager, settings: SettingsStore) {
        center = Self.makeNotificationCenterIfAvailable()
        self.database = database
        self.settings = settings
        super.init()
        if let center {
            center.delegate = self
            configureActions()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(settingsChanged),
                name: .jotSettingsDidChange,
                object: nil
            )
        }
    }

    deinit {
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    func bootstrap() {
        requestAuthorizationIfNeeded()
        scheduleMorningSummary()
        startPeriodicDueScan()
    }

    func requestAuthorizationIfNeeded() {
        guard let center else { return }
        center.requestAuthorization(options: [.alert]) { _, _ in }
    }

    func scheduleMorningSummary() {
        guard let center else { return }
        center.removePendingNotificationRequests(withIdentifiers: ["jot.morning.summary"])
        guard settings.notificationsEnabled, settings.summaryEnabled else { return }

        var components = DateComponents()
        components.hour = settings.summaryHour
        components.minute = settings.summaryMinute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let content = UNMutableNotificationContent()
        content.title = "Jot Summary"

        let dueCount = (try? database.dueTodayCount()) ?? 0
        content.body = dueCount == 0 ? "Nothing due today." : "\(dueCount) task(s) due today."
        content.sound = nil
        content.badge = 0

        let request = UNNotificationRequest(identifier: "jot.morning.summary", content: content, trigger: trigger)
        center.add(request)
    }

    func scheduleDueNotificationsIfNeeded(now: Date = .now, calendar: Calendar = .current) {
        guard let center else { return }
        guard settings.notificationsEnabled else { return }
        guard let tasks = try? database.fetchTasks(queue: .reachOut, status: .active) else { return }

        let today = calendar.startOfDay(for: now)
        let sent = sentNotificationSet(for: today)
        var newSent = sent

        for task in tasks {
            guard let due = task.dueDateValue else { continue }
            if calendar.isDate(due, inSameDayAs: today) {
                let key = "reachout|\(task.id)|\(dayKey(today, calendar: calendar))"
                if sent.contains(key) { continue }

                let content = UNMutableNotificationContent()
                content.title = "Follow Up Due"
                content.body = task.title
                content.categoryIdentifier = Self.categoryIdentifier
                content.sound = nil
                content.badge = 0

                let request = UNNotificationRequest(
                    identifier: key,
                    content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
                )
                center.add(request)
                newSent.insert(key)
            }
        }

        setSentNotificationSet(newSent, for: today)
    }

    func startPeriodicDueScan() {
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
        scheduleDueNotificationsIfNeeded(now: now)
        try? database.resurfaceOverdueReachOuts(now: now)
        _ = try? database.archiveOldTasks(now: now)
    }

    @objc private func settingsChanged() {
        scheduleMorningSummary()
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

    private func dayKey(_ date: Date, calendar: Calendar) -> String {
        let comp = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(comp.year ?? 0)-\(comp.month ?? 0)-\(comp.day ?? 0)"
    }

    private func sentNotificationSet(for date: Date) -> Set<String> {
        let key = "sentNotifications.\(dayKey(date, calendar: .current))"
        let value = UserDefaults.standard.array(forKey: key) as? [String] ?? []
        return Set(value)
    }

    private func setSentNotificationSet(_ set: Set<String>, for date: Date) {
        let key = "sentNotifications.\(dayKey(date, calendar: .current))"
        UserDefaults.standard.set(Array(set), forKey: key)
    }

    private static func makeNotificationCenterIfAvailable() -> UNUserNotificationCenter? {
        // `swift run` launches from a raw executable path (no .app bundle), where
        // UserNotifications can assert while resolving process bundle metadata.
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
        completionHandler([.banner, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        let actionIdentifier = response.actionIdentifier
        let parts = identifier.split(separator: "|")
        let taskID = parts.count >= 2 ? String(parts[1]) : nil

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
