#if canImport(XCTest)
import XCTest
@testable import Jot

final class InputCommandParserTests: XCTestCase {
    func testConsumesMeetingCommand() {
        let consumed = InputCommandParser.consumeLeadingCommand(from: "/meeting Planning sync")
        XCTAssertNotNil(consumed)
        XCTAssertEqual(consumed?.remainder, "Planning sync")
        XCTAssertEqual(consumed?.command.id, "meeting")
        XCTAssertEqual(consumed?.command.kind, .meetingStart)
    }

    func testConsumesThoughtDoubleSlash() {
        let consumed = InputCommandParser.consumeLeadingCommand(from: "// random idea")
        XCTAssertNotNil(consumed)
        XCTAssertEqual(consumed?.remainder, "random idea")
        XCTAssertEqual(consumed?.command.kind, .queue(.thought))
    }

    func testConsumesNoteCommand() {
        let consumed = InputCommandParser.consumeLeadingCommand(from: "/n random idea")
        XCTAssertNotNil(consumed)
        XCTAssertEqual(consumed?.remainder, "random idea")
        XCTAssertEqual(consumed?.command.kind, .queue(.thought))
    }

    func testConsumesAliasesCaseInsensitively() {
        let consumed = InputCommandParser.consumeLeadingCommand(from: "   /F ping Chris")
        XCTAssertNotNil(consumed)
        XCTAssertEqual(consumed?.remainder, "ping Chris")
        XCTAssertEqual(consumed?.command.kind, .queue(.reachOut))
    }

    func testExpandsFollowUpCommandRemainder() {
        let command = InputCommand(id: "reach_out", kind: .queue(.reachOut), trigger: "/f", label: "Follow Up", prompt: "")
        XCTAssertEqual(
            InputCommandParser.expandedRemainder(for: command, remainder: "Bob wednesday"),
            "follow up with Bob wednesday"
        )
    }

    func testUnknownCommandIsIgnored() {
        let consumed = InputCommandParser.consumeLeadingCommand(from: "/unknown ping Chris")
        XCTAssertNil(consumed)
    }

    func testConsumesTodayCommand() {
        let consumed = InputCommandParser.consumeLeadingCommand(from: "/t finish writeup")
        XCTAssertNotNil(consumed)
        XCTAssertEqual(consumed?.remainder, "finish writeup")
        XCTAssertEqual(consumed?.command.id, "today")
        XCTAssertEqual(consumed?.command.kind, .today)
    }
}
#endif
