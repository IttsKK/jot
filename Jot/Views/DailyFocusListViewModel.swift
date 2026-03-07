import Foundation

@MainActor
final class DailyFocusListViewModel: ObservableObject {
    @Published var tasks: [Task] = []

    private let database: DatabaseManager
    private var observer: NSObjectProtocol?

    init(database: DatabaseManager) {
        self.database = database
        observer = NotificationCenter.default.addObserver(forName: .jotDatabaseDidChange, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async {
                try? self?.refresh()
            }
        }
        try? refresh()
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    var dayKey: String {
        DatabaseManager.dayKey(for: .now)
    }

    var openCount: Int {
        tasks.filter { $0.status == .active }.count
    }

    func refresh() throws {
        tasks = try database.fetchDailyFocusTasks(dayKey: dayKey)
    }

    func toggleDone(_ task: Task) {
        try? database.toggleDone(id: task.id)
    }

    func removeFromToday(_ task: Task) {
        try? database.removeTaskDailyFocus(id: task.id)
    }

    func addFromTaskID(_ id: String) {
        try? database.setTaskDailyFocus(id: id)
    }
}
