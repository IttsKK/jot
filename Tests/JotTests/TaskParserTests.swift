#if canImport(XCTest)
import XCTest
@testable import Jot

final class TaskParserTests: XCTestCase {
    private let baselineNow = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 3, day: 3, hour: 9).date!
    private let calendar = Calendar(identifier: .gregorian)

    func testDefaultTaskParsing() {
        let parsed = TaskParser.parse("finish spec", now: baselineNow, calendar: calendar)
        XCTAssertEqual(parsed.type, .task)
        XCTAssertEqual(parsed.queue, .work)
        XCTAssertEqual(parsed.title, "finish spec")
        XCTAssertNil(parsed.dueDate)
    }

    func testFollowUpMapsToReachOutQueue() {
        let parsed = TaskParser.parse("follow up with Sarah", now: baselineNow, calendar: calendar)
        XCTAssertEqual(parsed.type, .followUp)
        XCTAssertEqual(parsed.queue, .reachOut)
        XCTAssertEqual(parsed.person, "Sarah")
    }

    func testFollowUpNameRecognitionWithoutPreposition() {
        let parsed = TaskParser.parse("follow up sarah tomorrow", now: baselineNow, calendar: calendar)
        XCTAssertEqual(parsed.queue, .reachOut)
        XCTAssertEqual(parsed.person, "sarah")
        XCTAssertEqual(parsed.title, "follow up sarah")
    }

    func testQueueOverrideWins() {
        let parsed = TaskParser.parse("follow up with Sarah /w", now: baselineNow, calendar: calendar)
        XCTAssertEqual(parsed.type, .followUp)
        XCTAssertEqual(parsed.queue, .work)
    }

    func testDateExtractionAndTitleCleanup() {
        let parsed = TaskParser.parse("send update by tomorrow", now: baselineNow, calendar: calendar)
        XCTAssertEqual(parsed.title, "send update")
        XCTAssertEqual(dayString(parsed.dueDate), "2026-03-04")
    }

    func testAbsoluteDateAndDescriptionExtraction() {
        let parsed = TaskParser.parse("email Chris march 5 about renewal terms", now: baselineNow, calendar: calendar)
        XCTAssertEqual(parsed.queue, .reachOut)
        XCTAssertEqual(parsed.person, "Chris")
        XCTAssertEqual(parsed.title, "email Chris")
        XCTAssertEqual(parsed.note, "renewal terms")
        XCTAssertEqual(dayString(parsed.dueDate), "2026-03-05")
    }

    func testNoteExtractionPreservesTypedCase() {
        let parsed = TaskParser.parse("email Chris about Q4 Plan", now: baselineNow, calendar: calendar)
        XCTAssertEqual(parsed.note, "Q4 Plan")
    }

    func testInDaysParsing() {
        let parsed = TaskParser.parse("draft report in 3 days", now: baselineNow, calendar: calendar)
        XCTAssertEqual(dayString(parsed.dueDate), "2026-03-06")
    }

    func testNextWeekWeekdayParsing() {
        let parsed = TaskParser.parse("follow up next week thursday", now: baselineNow, calendar: calendar)
        XCTAssertEqual(dayString(parsed.dueDate), "2026-03-12")
    }

    func testEndOfMonthParsing() {
        let parsed = TaskParser.parse("send invoice end of month", now: baselineNow, calendar: calendar)
        XCTAssertEqual(dayString(parsed.dueDate), "2026-03-31")
    }

    func testParserPerformanceTarget() {
        let sample = "follow up with Dana tomorrow about roadmap"
        let iterations = 10_000

        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations {
            _ = TaskParser.parse(sample, now: baselineNow, calendar: calendar)
        }
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        let averageMilliseconds = Double(elapsed) / Double(iterations) / 1_000_000.0

        XCTAssertLessThan(averageMilliseconds, 1.0)
    }

    private func dayString(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
#endif
