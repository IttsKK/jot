#if canImport(XCTest)
import XCTest
@testable import Jot

final class TaskTextFormatterTests: XCTestCase {
    func testFormatsTitleCase() {
        let formatted = TaskTextFormatter.formattedTitle("follow up with the design team")
        XCTAssertEqual(formatted, "Follow Up with the Design Team")
    }

    func testFormatsPersonCase() {
        let formatted = TaskTextFormatter.formattedPerson("sarah o'connor")
        XCTAssertEqual(formatted, "Sarah O'Connor")
    }

    func testKeepsPossessiveApostropheSuffixLowercase() {
        let formatted = TaskTextFormatter.formattedTitle("follow up with david's assistant")
        XCTAssertEqual(formatted, "Follow Up with David's Assistant")
    }

    func testFormatsNoteSentenceCase() {
        let formatted = TaskTextFormatter.formattedNote("send Q4 update")
        XCTAssertEqual(formatted, "Send Q4 update")
    }

    func testPreservesSpecialTokens() {
        let formatted = TaskTextFormatter.formattedTitle("review ios api and sql migration")
        XCTAssertEqual(formatted, "Review iOS API and SQL Migration")
    }
}
#endif
