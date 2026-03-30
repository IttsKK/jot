import Foundation

enum TaskParser {
    static let defaultDueHour = 9
    static let defaultDueMinute = 0

    static func consumeLeadingModePrefix(from input: String) -> (queue: TaskQueue, remainder: String)? {
        guard let consumed = InputCommandParser.consumeLeadingCommand(from: input) else {
            return nil
        }
        guard case let .queue(queue) = consumed.command.kind else { return nil }
        return (queue, consumed.remainder)
    }

    static func parse(
        _ input: String,
        now: Date = .now,
        calendar: Calendar = .current,
        fallbackToRawTitle: Bool = true
    ) -> ParsedTask {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty {
            return ParsedTask(rawInput: input, title: "", type: .task, queue: .work, person: nil, dueDate: nil, note: nil)
        }

        var working = raw
        let leadingMode = consumeLeadingModePrefix(from: working)
        if let leadingMode {
            working = InputCommandParser.expandedRemainder(
                for: InputCommand(
                    id: "",
                    kind: .queue(leadingMode.queue),
                    trigger: "",
                    label: "",
                    prompt: ""
                ),
                remainder: leadingMode.remainder
            )
            if leadingMode.queue == .thought {
                let title = cleanupTitle(working)
                return ParsedTask(
                    rawInput: raw,
                    title: title,
                    type: .thought,
                    queue: .thought,
                    person: nil,
                    dueDate: nil,
                    note: nil
                )
            }
        }

        let override = queueOverride(in: working)
        if override != nil {
            working = strippingRegex(#"(?:^|\s)/(?:w|r)(?=\s|$)"#, from: working)
        }

        let type = detectType(in: working)
        var queue: TaskQueue
        if let leadingMode {
            queue = leadingMode.queue
        } else if let override {
            queue = override
        } else {
            queue = (type == .followUp) ? .reachOut : .work
        }

        let (dueDate, withoutDate) = extractDate(from: working, now: now, calendar: calendar)
        working = withoutDate

        let (note, withoutNote) = extractNote(from: working)
        working = withoutNote

        var person: String?
        if queue == .reachOut {
            person = extractPerson(from: working)
        }

        let title = cleanupTitle(working)

        let finalTitle: String
        if title.isEmpty && fallbackToRawTitle {
            finalTitle = leadingMode == nil ? raw : working
        } else {
            finalTitle = title
        }

        return ParsedTask(
            rawInput: raw,
            title: finalTitle,
            type: type,
            queue: queue,
            person: person,
            dueDate: dueDate,
            note: note
        )
    }

    private static func queueOverride(in input: String) -> TaskQueue? {
        let pattern = #"(?:^|\s)/(w|r)(?=\s|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let ns = input as NSString
        let matches = regex.matches(in: input, range: NSRange(location: 0, length: ns.length))
        guard let last = matches.last else { return nil }
        let token = ns.substring(with: last.range(at: 1)).lowercased()
        return token == "r" ? .reachOut : .work
    }

    private static func detectType(in input: String) -> ParsedTaskType {
        let lower = input.lowercased()
        let followUpPhrases = [
            "follow up", "follow-up", "check in", "check-in", "reach out", "email", "call", "text", "ping", "contact", "message"
        ]

        if followUpPhrases.contains(where: { lower.contains($0) }) || hasRemindFollowUpSignal(in: input) {
            return .followUp
        }

        return .task
    }

    private static func extractDate(from input: String, now: Date, calendar: Calendar) -> (Date?, String) {
        let lower = input.lowercased()

        if let matched = firstMatch(#"\bin\s+(\d{1,3})\s+(hour|hours|hr|hrs|minute|minutes|min|mins)\b"#, in: lower),
           let valueToken = matched.captures[0],
           let value = Int(valueToken) {
            let unit = matched.captures[1] ?? "hours"
            let component: Calendar.Component = unit.hasPrefix("min") ? .minute : .hour
            let date = calendar.date(byAdding: component, value: value, to: now)
            return (date, removeToken(from: input, lower: lower, range: matched.range))
        }

        func finalizeDate(_ day: Date, dateRange: NSRange) -> (Date?, String) {
            let withoutDate = removeToken(from: input, lower: lower, range: dateRange)
            let (timeComponents, withoutTime) = extractTime(from: withoutDate)
            let resolvedDate = applyingTime(timeComponents, to: day, calendar: calendar)
            return (resolvedDate, withoutTime)
        }

        let quickTokens: [(String, Int)] = [
            ("today", 0),
            ("tonight", 0),
            ("tomorrow", 1),
            ("tmrw", 1)
        ]

        for token in quickTokens {
            if let range = findTokenRange(token.0, in: lower) {
                guard let day = calendar.date(byAdding: .day, value: token.1, to: now) else { continue }
                return finalizeDate(day, dateRange: range)
            }
        }

        if let matched = firstMatch(nextWeekWeekdayPattern, in: lower),
           let dayToken = matched.captures.compactMap({ $0 }).first,
           let targetWeekday = weekdayNumber(for: dayToken),
           let currentWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)),
           let nextWeekStart = calendar.date(byAdding: .weekOfYear, value: 1, to: currentWeekStart),
           let date = calendar.nextDate(
               after: nextWeekStart.addingTimeInterval(-1),
               matching: DateComponents(weekday: targetWeekday),
               matchingPolicy: .nextTime,
               direction: .forward
           ) {
            return finalizeDate(date, dateRange: matched.range)
        }

        if let range = findTokenRange("next week", in: lower),
           let date = calendar.date(byAdding: .day, value: 7, to: now) {
            return finalizeDate(date, dateRange: range)
        }

        if let range = findTokenRange("next month", in: lower),
           let date = calendar.date(byAdding: .month, value: 1, to: now) {
            return finalizeDate(date, dateRange: range)
        }

        if let range = findTokenRange("end of week", in: lower) {
            let weekday = calendar.component(.weekday, from: now)
            let daysUntilSunday = (8 - weekday) % 7
            if let target = calendar.date(byAdding: .day, value: daysUntilSunday, to: now) {
                return finalizeDate(target, dateRange: range)
            }
        }

        if let range = findTokenRange("end of month", in: lower) {
            var components = calendar.dateComponents([.year, .month], from: now)
            components.month = (components.month ?? 1) + 1
            components.day = 0
            let target = calendar.date(from: components)
            if let target {
                return finalizeDate(target, dateRange: range)
            }
        }

        if let matched = firstMatch(#"\bin\s+(\d{1,2})\s+(day|days|week|weeks|month|months)\b"#, in: lower) {
            let value = Int(matched.captures[0] ?? "") ?? 0
            let unit = matched.captures[1] ?? "days"
            let component: Calendar.Component
            switch unit {
            case "week", "weeks":
                component = .day
            case "month", "months":
                component = .month
            default:
                component = .day
            }
            let amount = (unit == "week" || unit == "weeks") ? value * 7 : value
            if let date = calendar.date(byAdding: component, value: amount, to: now) {
                return finalizeDate(date, dateRange: matched.range)
            }
        }

        let weekdays = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        for (index, day) in weekdays.enumerated() {
            if let range = findTokenRange(day, in: lower) {
                let currentWeekday = calendar.component(.weekday, from: now)
                let targetWeekday = index + 2
                var delta = targetWeekday - currentWeekday
                if delta <= 0 {
                    delta += 7
                }
                if let date = calendar.date(byAdding: .day, value: delta, to: now) {
                    return finalizeDate(date, dateRange: range)
                }
            }
        }

        if let matched = firstMatch(#"\b(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+(\d{1,2})\b"#, in: lower),
           let monthToken = matched.captures[0],
           let dayToken = matched.captures[1],
           let month = monthNumber(monthToken),
           let day = Int(dayToken) {
            let candidate = absoluteDate(month: month, day: day, year: nil, now: now, calendar: calendar)
            if let candidate {
                return finalizeDate(candidate, dateRange: matched.range)
            }
        }

        if let matched = firstMatch(#"\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b"#, in: lower),
           let monthToken = matched.captures[0],
           let dayToken = matched.captures[1],
           let month = Int(monthToken),
           let day = Int(dayToken) {
            let yearToken = matched.captures[2].flatMap(Int.init)
            let year = normalizeYear(yearToken, currentYear: calendar.component(.year, from: now))
            let candidate = absoluteDate(month: month, day: day, year: year, now: now, calendar: calendar)
            if let candidate {
                return finalizeDate(candidate, dateRange: matched.range)
            }
        }

        if let matched = firstMatch(#"\bthe\s+(\d{1,2})(?:st|nd|rd|th)\b"#, in: lower),
           let dayToken = matched.captures[0],
           let day = Int(dayToken) {
            let nowMonth = calendar.component(.month, from: now)
            let candidate = absoluteDate(month: nowMonth, day: day, year: nil, now: now, calendar: calendar)
            if let candidate {
                return finalizeDate(candidate, dateRange: matched.range)
            }
        }

        return (nil, input)
    }

    static func parseTimeComponents(from input: String, allowBareNumericTime: Bool = false) -> DateComponents? {
        timeExtraction(from: input, allowBareNumericTime: allowBareNumericTime)?.components
    }

    private static func extractTime(from input: String) -> (DateComponents?, String) {
        let lower = input.lowercased()
        guard let extraction = timeExtraction(from: input) else {
            return (nil, input)
        }

        let remaining = removeToken(from: input, lower: lower, range: extraction.range)
        return (extraction.components, remaining)
    }

    private static func timeExtraction(from input: String, allowBareNumericTime: Bool = false) -> TimeExtraction? {
        let lower = input.lowercased()

        if let matched = firstMatch(#"\b(noon|midday|midnight)\b"#, in: lower),
           let token = matched.captures[0] {
            let hour = token == "midnight" ? 0 : 12
            return TimeExtraction(range: matched.range, components: DateComponents(hour: hour, minute: 0, second: 0))
        }

        if let matched = firstMatch(#"\b(\d{1,2})(?::([0-5]\d))?\s*([ap])\.?m\.?\b"#, in: lower),
           let hourToken = matched.captures[0],
           let rawHour = Int(hourToken),
           (1...12).contains(rawHour) {
            let minute = Int(matched.captures[1] ?? "") ?? 0
            let meridiem = matched.captures[2] ?? "a"
            let normalizedHour = (rawHour % 12) + (meridiem == "p" ? 12 : 0)
            return TimeExtraction(
                range: matched.range,
                components: DateComponents(hour: normalizedHour, minute: minute, second: 0)
            )
        }

        if let matched = firstMatch(#"\b(\d{1,2}):([0-5]\d)\b"#, in: lower),
           let hourToken = matched.captures[0],
           let minuteToken = matched.captures[1],
           let rawHour = Int(hourToken),
           let minute = Int(minuteToken),
           let hour = normalizedHour(for: rawHour, token: hourToken) {
            return TimeExtraction(
                range: matched.range,
                components: DateComponents(hour: hour, minute: minute, second: 0)
            )
        }

        if let matched = firstMatch(#"\b(?:at|by|around)\s+(\d{1,2})\b"#, in: lower),
           let hourToken = matched.captures[0],
           let rawHour = Int(hourToken),
           let hour = normalizedHour(for: rawHour, token: hourToken) {
            return TimeExtraction(
                range: matched.range,
                components: DateComponents(hour: hour, minute: 0, second: 0)
            )
        }

        if allowBareNumericTime,
           let matched = firstMatch(#"\b(\d{1,2})\b"#, in: lower),
           let hourToken = matched.captures[0],
           let rawHour = Int(hourToken),
           let hour = normalizedHour(for: rawHour, token: hourToken) {
            return TimeExtraction(
                range: matched.range,
                components: DateComponents(hour: hour, minute: 0, second: 0)
            )
        }

        return nil
    }

    private static func normalizedHour(for rawHour: Int, token: String) -> Int? {
        guard (0...23).contains(rawHour) else { return nil }
        if token.count > 1, token.hasPrefix("0") {
            return rawHour
        }

        switch rawHour {
        case 1...7:
            return rawHour + 12
        case 0, 12...23:
            return rawHour
        default:
            return rawHour
        }
    }

    private static func extractNote(from input: String) -> (String?, String) {
        if hasRemindFollowUpSignal(in: input) {
            return (nil, input)
        }

        let pattern = #"\b(?:about|regarding|re:)\s+(.+)$"#
        guard let match = firstMatch(pattern, in: input),
              let rawRange = Range(match.range, in: input),
              let note = match.captures[0] else {
            return (nil, input)
        }

        var remaining = input
        remaining.removeSubrange(rawRange)
        return (cleanupTitle(note), cleanupTitle(remaining))
    }

    private static func extractPerson(from input: String) -> String? {
        let remindPersonPattern = #"\bremind\s+(?!me\b)([A-Za-z][A-Za-z'\-]*(?:\s+[A-Za-z][A-Za-z'\-]*){0,2}?)(?=\s+(?:about|regarding|re:|today|tonight|tomorrow|tmrw|next\b|monday|mon|tuesday|tue|tues|wednesday|wed|thursday|thu|thur|thurs|friday|fri|saturday|sat|sunday|sun|jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?|in\b|at\b|by\b|around\b|/w\b|/r\b)|$)"#
        if let match = firstMatch(remindPersonPattern, in: input),
           let person = match.captures[0] {
            return cleanupTitle(person)
        }

        if let match = firstMatch(#"\b(follow\s*up|follow-up|check\s*in|check-in|reach\s*out)\s+(?!with\b|to\b)([A-Za-z][A-Za-z'\-]*(?:\s+[A-Za-z][A-Za-z'\-]*){0,2})\b"#, in: input),
           let person = match.captures[1] {
            return cleanupTitle(person)
        }

        if let match = firstMatch(#"\b(email|call|text|ping|message)\s+([A-Za-z][A-Za-z'\-]*(?:\s+[A-Za-z][A-Za-z'\-]*){0,2})\b"#, in: input),
           let person = match.captures[1] {
            return cleanupTitle(person)
        }

        if let match = firstMatch(#"\b(?:with|to)\s+([A-Za-z][A-Za-z'\-]*(?:\s+[A-Za-z][A-Za-z'\-]*){0,2})\b"#, in: input),
           let person = match.captures[0] {
            return cleanupTitle(person)
        }

        return nil
    }

    private static func hasRemindFollowUpSignal(in input: String) -> Bool {
        firstMatch(#"\bremind\s+(?!me\b)[A-Za-z][A-Za-z'\-]*\b"#, in: input) != nil
    }

    private static func cleanupTitle(_ input: String) -> String {
        var result = input
        result = strippingRegex(#"\s+"#, from: result, with: " ")
        result = strippingRegex(#"\s+([,.;:])"#, from: result, with: "$1")
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-,:;"))
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func findTokenRange(_ token: String, in lowerText: String) -> NSRange? {
        let escaped = NSRegularExpression.escapedPattern(for: token)
        let pattern = "\\b\(escaped)\\b"
        return firstMatch(pattern, in: lowerText)?.range
    }

    private static func removeToken(from original: String, lower: String, range: NSRange) -> String {
        let ns = lower as NSString
        var expanded = range

        let prefix = ns.substring(to: range.location)
        if let prepMatch = firstMatch(#"(?:\bby|\bon|\bat|\bfor|\bdue|\bbefore)\s+$"#, in: prefix) {
            expanded = NSRange(location: prepMatch.range.location, length: range.location + range.length - prepMatch.range.location)
        }

        var result = original
        if let swiftRange = Range(expanded, in: result) {
            result.removeSubrange(swiftRange)
        }
        return cleanupTitle(result)
    }

    private static func firstMatch(_ pattern: String, in input: String) -> RegexMatch? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let ns = input as NSString
        guard let match = regex.firstMatch(in: input, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }

        var captures: [String?] = []
        if match.numberOfRanges > 1 {
            for idx in 1..<match.numberOfRanges {
                let captureRange = match.range(at: idx)
                if captureRange.location == NSNotFound {
                    captures.append(nil)
                } else {
                    captures.append(ns.substring(with: captureRange))
                }
            }
        }

        return RegexMatch(range: match.range, captures: captures)
    }

    private static func strippingRegex(_ pattern: String, from input: String, with template: String = "") -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return input
        }
        let ns = input as NSString
        return regex.stringByReplacingMatches(in: input, range: NSRange(location: 0, length: ns.length), withTemplate: template)
    }

    private static func monthNumber(_ token: String) -> Int? {
        let map: [String: Int] = [
            "jan": 1, "january": 1,
            "feb": 2, "february": 2,
            "mar": 3, "march": 3,
            "apr": 4, "april": 4,
            "may": 5,
            "jun": 6, "june": 6,
            "jul": 7, "july": 7,
            "aug": 8, "august": 8,
            "sep": 9, "sept": 9, "september": 9,
            "oct": 10, "october": 10,
            "nov": 11, "november": 11,
            "dec": 12, "december": 12
        ]
        return map[token.lowercased()]
    }

    private static func weekdayNumber(for token: String) -> Int? {
        switch token.lowercased() {
        case "sunday", "sun": return 1
        case "monday", "mon": return 2
        case "tuesday", "tue", "tues": return 3
        case "wednesday", "wed": return 4
        case "thursday", "thu", "thur", "thurs": return 5
        case "friday", "fri": return 6
        case "saturday", "sat": return 7
        default: return nil
        }
    }

    private static func normalizeYear(_ parsed: Int?, currentYear: Int) -> Int? {
        guard let parsed else { return nil }
        if parsed < 100 {
            let century = (currentYear / 100) * 100
            return century + parsed
        }
        return parsed
    }

    private static func absoluteDate(
        month: Int,
        day: Int,
        year: Int?,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        var components = calendar.dateComponents([.year], from: now)
        components.month = month
        components.day = day
        components.hour = defaultDueHour
        components.minute = defaultDueMinute
        components.second = 0

        if let year {
            components.year = year
            return calendar.date(from: components)
        }

        guard let candidate = calendar.date(from: components) else {
            return nil
        }

        if candidate >= calendar.startOfDay(for: now) {
            return candidate
        }

        components.year = (components.year ?? 0) + 1
        return calendar.date(from: components)
    }

    private static func defaultDueDate(on day: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: DateComponents(hour: defaultDueHour, minute: defaultDueMinute), to: start) ?? start
    }

    private static func applyingTime(_ time: DateComponents?, to day: Date, calendar: Calendar) -> Date {
        guard let time else {
            return defaultDueDate(on: day, calendar: calendar)
        }

        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0
        return calendar.date(from: components) ?? defaultDueDate(on: day, calendar: calendar)
    }
}

private struct RegexMatch {
    var range: NSRange
    var captures: [String?]
}

private struct TimeExtraction {
    var range: NSRange
    var components: DateComponents
}

private let nextWeekWeekdayPattern = #"\b(?:next\s+week\s+(?:on\s+)?(monday|mon|tuesday|tue|tues|wednesday|wed|thursday|thu|thur|thurs|friday|fri|saturday|sat|sunday|sun)|(monday|mon|tuesday|tue|tues|wednesday|wed|thursday|thu|thur|thurs|friday|fri|saturday|sat|sunday|sun)\s+next\s+week)\b"#
