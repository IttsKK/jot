#if canImport(XCTest)
import XCTest
@testable import Jot

final class TaskDueFormatterTests: XCTestCase {
    func testCompactLabelOmitsDefaultMorningTime() {
        let calendar = makeCalendar()
        let now = makeDate(2026, 3, 29, 8, 0, calendar: calendar)
        let due = makeDate(2026, 3, 30, 9, 0, calendar: calendar)

        let label = TaskDueFormatter.compactLabel(
            for: due,
            now: now,
            calendar: calendar,
            locale: Locale(identifier: "en_US_POSIX")
        )

        XCTAssertEqual(label, "Tomorrow")
    }

    func testCompactLabelIncludesExplicitTime() {
        let calendar = makeCalendar()
        let now = makeDate(2026, 3, 29, 8, 0, calendar: calendar)
        let due = makeDate(2026, 3, 30, 11, 15, calendar: calendar)

        let label = TaskDueFormatter.compactLabel(
            for: due,
            now: now,
            calendar: calendar,
            locale: Locale(identifier: "en_US_POSIX")
        )

        XCTAssertTrue(label.hasPrefix("Tomorrow · 11:15"))
        XCTAssertTrue(label.hasSuffix("AM"))
    }

    func testCompactLabelUsesShortDateForFartherDates() {
        let calendar = makeCalendar()
        let now = makeDate(2026, 3, 29, 8, 0, calendar: calendar)
        let due = makeDate(2026, 4, 10, 9, 0, calendar: calendar)

        let label = TaskDueFormatter.compactLabel(
            for: due,
            now: now,
            calendar: calendar,
            locale: Locale(identifier: "en_US_POSIX")
        )

        XCTAssertEqual(label, "Apr 10")
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Vancouver")!
        return calendar
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, calendar: Calendar) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return components.date!
    }
}
#endif
