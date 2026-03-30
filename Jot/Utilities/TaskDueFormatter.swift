import Foundation

enum TaskDueFormatter {
    static func compactLabel(
        for date: Date,
        now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let dayLabel = relativeDayLabel(for: date, now: now, calendar: calendar, locale: locale)
        guard hasExplicitTime(date, calendar: calendar) else { return dayLabel }
        return "\(dayLabel) · \(timeFormatter(locale: locale, timeZone: calendar.timeZone).string(from: date))"
    }

    static func detailLabel(
        for date: Date,
        now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let dayLabel = relativeDayLabel(for: date, now: now, calendar: calendar, locale: locale)
        guard hasExplicitTime(date, calendar: calendar) else { return dayLabel }
        return "\(dayLabel) at \(timeFormatter(locale: locale, timeZone: calendar.timeZone).string(from: date))"
    }

    static func hasExplicitTime(_ date: Date, calendar: Calendar = .current) -> Bool {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        if hour == 0 && minute == 0 { return false }
        return !(hour == TaskParser.defaultDueHour && minute == TaskParser.defaultDueMinute)
    }

    private static func relativeDayLabel(
        for date: Date,
        now: Date,
        calendar: Calendar,
        locale: Locale
    ) -> String {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfDueDay = calendar.startOfDay(for: date)
        let dayDelta = calendar.dateComponents([.day], from: startOfToday, to: startOfDueDay).day ?? 0

        switch dayDelta {
        case 0:
            return "Today"
        case 1:
            return "Tomorrow"
        case -1:
            return "Yesterday"
        case 2...6:
            return weekdayFormatter(locale: locale, timeZone: calendar.timeZone).string(from: date)
        default:
            return dateLabel(for: date, now: now, calendar: calendar, locale: locale)
        }
    }

    private static func dateLabel(
        for date: Date,
        now: Date,
        calendar: Calendar,
        locale: Locale
    ) -> String {
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return monthDayFormatter(locale: locale, timeZone: calendar.timeZone).string(from: date)
        }
        return monthDayYearFormatter(locale: locale, timeZone: calendar.timeZone).string(from: date)
    }

    private static func weekdayFormatter(locale: Locale, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }

    private static func monthDayFormatter(locale: Locale, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }

    private static func monthDayYearFormatter(locale: Locale, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMM d yyyy")
        return formatter
    }

    private static func timeFormatter(locale: Locale, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }
}
