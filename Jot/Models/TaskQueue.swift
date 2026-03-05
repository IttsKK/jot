import Foundation
import GRDB

enum TaskQueue: String, Codable, CaseIterable, Sendable, DatabaseValueConvertible {
    case work
    case reachOut = "reach_out"
    case thought

    var displayName: String {
        switch self {
        case .work: return "Work"
        case .reachOut: return "Follow Up"
        case .thought: return "Thought"
        }
    }
}
