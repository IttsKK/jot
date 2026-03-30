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

    func testLeadingModePrefixWithoutSpaceIsConsumed() {
        let parsed = TaskParser.parse("/w", now: baselineNow, calendar: calendar)
        XCTAssertEqual(parsed.queue, .work)
        XCTAssertEqual(parsed.title, "")
    }

    func testLeadingThoughtModePrefixSetsThoughtQueue() {
        let parsed = TaskParser.parse("/n idea to revisit", now: baselineNow, calendar: calendar)
        XCTAssertEqual(parsed.queue, .thought)
        XCTAssertEqual(parsed.type, .thought)
        XCTAssertEqual(parsed.title, "idea to revisit")
    }

    func testFollowUpCommandExpandsIntoFollowUpTitleAndDate() {
        let parsed = TaskParser.parse("/f Bob wednesday", now: baselineNow, calendar: calendar)
        XCTAssertEqual(parsed.queue, .reachOut)
        XCTAssertEqual(parsed.type, .followUp)
        XCTAssertEqual(parsed.person, "Bob")
        XCTAssertEqual(parsed.title, "follow up with Bob")
        XCTAssertEqual(dayString(parsed.dueDate), "2026-03-04")
    }

    func testDateExtractionAndTitleCleanup() {
        let parsed = TaskParser.parse("send update by tomorrow", now: baselineNow, calendar: calendar)
        XCTAssertEqual(parsed.title, "send update")
        XCTAssertEqual(dayString(parsed.dueDate), "2026-03-04")
        XCTAssertEqual(timeString(parsed.dueDate), "09:00")
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

    func testRemindPersonTriggersFollowUpWithoutSplittingAboutClause() {
        let parsed = TaskParser.parse("remind Sarah about roadmap", now: baselineNow, calendar: calendar)
        XCTAssertEqual(parsed.type, .followUp)
        XCTAssertEqual(parsed.queue, .reachOut)
        XCTAssertEqual(parsed.person, "Sarah")
        XCTAssertEqual(parsed.title, "remind Sarah about roadmap")
        XCTAssertNil(parsed.note)
    }

    func testInDaysParsing() {
        let parsed = TaskParser.parse("draft report in 3 days", now: baselineNow, calendar: calendar)
        XCTAssertEqual(dayString(parsed.dueDate), "2026-03-06")
        XCTAssertEqual(timeString(parsed.dueDate), "09:00")
    }

    func testInHoursParsing() {
        let parsed = TaskParser.parse("follow up in 12 hours", now: baselineNow, calendar: calendar)
        XCTAssertEqual(dayString(parsed.dueDate), "2026-03-03")
        XCTAssertEqual(timeString(parsed.dueDate), "21:00")
        XCTAssertEqual(parsed.title, "follow up")
    }

    func testTomorrowAtTwelveParsing() {
        let parsed = TaskParser.parse("email Chris tomorrow at 12", now: baselineNow, calendar: calendar)
        XCTAssertEqual(parsed.queue, .reachOut)
        XCTAssertEqual(parsed.person, "Chris")
        XCTAssertEqual(dayString(parsed.dueDate), "2026-03-04")
        XCTAssertEqual(timeString(parsed.dueDate), "12:00")
        XCTAssertEqual(parsed.title, "email Chris")
    }

    func testAmbiguousBareHourDefaultsToAfternoonForEarlyHours() {
        let parsed = TaskParser.parse("email Chris tomorrow at 1", now: baselineNow, calendar: calendar)
        XCTAssertEqual(dayString(parsed.dueDate), "2026-03-04")
        XCTAssertEqual(timeString(parsed.dueDate), "13:00")
    }

    func testExplicitMeridiemOverridesDefaultHourHeuristic() {
        let noon = TaskParser.parse("email Chris tomorrow at 12pm", now: baselineNow, calendar: calendar)
        XCTAssertEqual(timeString(noon.dueDate), "12:00")

        let midnight = TaskParser.parse("email Chris tomorrow at 12am", now: baselineNow, calendar: calendar)
        XCTAssertEqual(timeString(midnight.dueDate), "00:00")
    }

    func testNamedTimesAreRecognized() {
        let noon = TaskParser.parse("email Chris tomorrow at noon", now: baselineNow, calendar: calendar)
        XCTAssertEqual(timeString(noon.dueDate), "12:00")

        let midnight = TaskParser.parse("email Chris tomorrow at midnight", now: baselineNow, calendar: calendar)
        XCTAssertEqual(timeString(midnight.dueDate), "00:00")
    }

    func testNextWeekWeekdayParsing() {
        let parsed = TaskParser.parse("follow up next week thursday", now: baselineNow, calendar: calendar)
        XCTAssertEqual(dayString(parsed.dueDate), "2026-03-12")
    }

    func testNextWeekTuesdayParsing() {
        let parsed = TaskParser.parse("ship notes next week tuesday", now: baselineNow, calendar: calendar)
        XCTAssertEqual(dayString(parsed.dueDate), "2026-03-10")
        XCTAssertEqual(parsed.title, "ship notes")
    }

    func testNextWeekWeekdayWithOnParsing() {
        let parsed = TaskParser.parse("ship notes next week on tuesday", now: baselineNow, calendar: calendar)
        XCTAssertEqual(dayString(parsed.dueDate), "2026-03-10")
        XCTAssertEqual(parsed.title, "ship notes")
    }

    func testWeekdayThenNextWeekParsing() {
        let parsed = TaskParser.parse("ship notes tuesday next week", now: baselineNow, calendar: calendar)
        XCTAssertEqual(dayString(parsed.dueDate), "2026-03-10")
        XCTAssertEqual(parsed.title, "ship notes")
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

    private func timeString(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
#endif
