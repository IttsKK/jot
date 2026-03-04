import Foundation
import GRDB

enum TaskStatus: String, Codable, CaseIterable, Sendable, DatabaseValueConvertible {
    case active
    case done
    case archived
}
