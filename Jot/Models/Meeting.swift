import Foundation
import GRDB

struct Meeting: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    static let databaseTableName = "meetings"

    var id: String
    var title: String
    var attendees: String?
    var summary: String?
    var startedAt: String
    var endedAt: String?

    enum Columns {
        static let id = Column("id")
        static let title = Column("title")
        static let attendees = Column("attendees")
        static let summary = Column("summary")
        static let startedAt = Column("started_at")
        static let endedAt = Column("ended_at")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case attendees
        case summary
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        attendees: String? = nil,
        summary: String? = nil,
        startedAt: Date = .now,
        endedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.attendees = attendees
        self.summary = summary
        self.startedAt = DateCodec.string(from: startedAt)
        self.endedAt = endedAt.map(DateCodec.string(from:))
    }

    var startedAtValue: Date? {
        DateCodec.date(from: startedAt)
    }

    var endedAtValue: Date? {
        DateCodec.date(from: endedAt)
    }

    var isActive: Bool {
        endedAt == nil
    }

    var attendeeList: [String] {
        guard let attendees, !attendees.isEmpty else { return [] }
        return attendees.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var duration: TimeInterval? {
        guard let start = startedAtValue else { return nil }
        let end = endedAtValue ?? Date()
        return end.timeIntervalSince(start)
    }

    var formattedDuration: String {
        guard let duration else { return "" }
        let minutes = Int(duration / 60)
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let rem = minutes % 60
        return rem > 0 ? "\(hours)h \(rem)m" : "\(hours)h"
    }
}
