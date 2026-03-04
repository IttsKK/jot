import Foundation
import GRDB

struct Task: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    static let databaseTableName = "tasks"

    var id: String
    var rawInput: String
    var title: String
    var queue: TaskQueue
    var status: TaskStatus
    var person: String?
    var dueDate: String?
    var note: String?
    var doneAt: String?
    var createdAt: String
    var position: Int64

    enum Columns {
        static let id = Column("id")
        static let rawInput = Column("raw_input")
        static let title = Column("title")
        static let queue = Column("queue")
        static let status = Column("status")
        static let person = Column("person")
        static let dueDate = Column("due_date")
        static let note = Column("note")
        static let doneAt = Column("done_at")
        static let createdAt = Column("created_at")
        static let position = Column("position")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case rawInput = "raw_input"
        case title
        case queue
        case status
        case person
        case dueDate = "due_date"
        case note
        case doneAt = "done_at"
        case createdAt = "created_at"
        case position
    }

    init(
        id: String = UUID().uuidString,
        rawInput: String,
        title: String,
        queue: TaskQueue = .work,
        status: TaskStatus = .active,
        person: String? = nil,
        dueDate: Date? = nil,
        note: String? = nil,
        doneAt: Date? = nil,
        createdAt: Date = .now,
        position: Int64 = 0
    ) {
        self.id = id
        self.rawInput = rawInput
        self.title = title
        self.queue = queue
        self.status = status
        self.person = person
        self.dueDate = dueDate.map(DateCodec.string(from:))
        self.note = note
        self.doneAt = doneAt.map(DateCodec.string(from:))
        self.createdAt = DateCodec.string(from: createdAt)
        self.position = position
    }

    var dueDateValue: Date? {
        DateCodec.date(from: dueDate)
    }

    var doneAtValue: Date? {
        DateCodec.date(from: doneAt)
    }

    var createdAtValue: Date? {
        DateCodec.date(from: createdAt)
    }
}
