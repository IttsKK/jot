import Foundation
import GRDB

struct DailyFocusItem: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    static let databaseTableName = "daily_focus_items"

    var id: String
    var dayKey: String
    var title: String
    var isDone: Bool
    var sourceTaskId: String?
    var createdAt: String
    var position: Int64

    enum Columns {
        static let id = Column("id")
        static let dayKey = Column("day_key")
        static let title = Column("title")
        static let isDone = Column("is_done")
        static let sourceTaskId = Column("source_task_id")
        static let createdAt = Column("created_at")
        static let position = Column("position")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case dayKey = "day_key"
        case title
        case isDone = "is_done"
        case sourceTaskId = "source_task_id"
        case createdAt = "created_at"
        case position
    }

    init(
        id: String = UUID().uuidString,
        dayKey: String,
        title: String,
        isDone: Bool = false,
        sourceTaskId: String? = nil,
        createdAt: Date = .now,
        position: Int64 = 0
    ) {
        self.id = id
        self.dayKey = dayKey
        self.title = title
        self.isDone = isDone
        self.sourceTaskId = sourceTaskId
        self.createdAt = DateCodec.string(from: createdAt)
        self.position = position
    }
}
