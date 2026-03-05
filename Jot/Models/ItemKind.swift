import Foundation
import GRDB

enum ItemKind: String, Codable, CaseIterable, Sendable, DatabaseValueConvertible {
    case task = "task"
    case thought = "thought"
}
