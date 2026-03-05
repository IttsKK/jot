import Foundation

enum ParsedTaskType: String, Sendable {
    case followUp = "follow_up"
    case task
    case thought
}

struct ParsedTask: Equatable, Sendable {
    var rawInput: String
    var title: String
    var type: ParsedTaskType
    var queue: TaskQueue
    var person: String?
    var dueDate: Date?
    var note: String?
}
