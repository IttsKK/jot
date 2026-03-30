import Foundation

enum TaskTextFormatter {
    private static let lowercasedWords: Set<String> = [
        "a", "an", "and", "as", "at", "but", "by", "for", "in", "of", "on", "or", "the", "to", "via", "vs", "with"
    ]

    private static let specialCasing: [String: String] = [
        "ios": "iOS",
        "macos": "macOS",
        "api": "API",
        "sql": "SQL",
        "ui": "UI",
        "ux": "UX",
        "llm": "LLM"
    ]

    private static let lowercaseApostropheSuffixes: Set<String> = [
        "s", "t", "d", "ll", "re", "ve", "m"
    ]

    static func formattedTitle(_ title: String) -> String {
        let cleaned = normalizeWhitespace(title)
        guard !cleaned.isEmpty else { return "" }

        let words = cleaned.split(separator: " ").map(String.init)
        var formatted: [String] = []

        for (index, word) in words.enumerated() {
            formatted.append(
                formatWord(
                    word,
                    isFirst: index == 0,
                    isLast: index == words.count - 1
                )
            )
        }

        return formatted.joined(separator: " ")
    }

    static func formattedPerson(_ person: String?) -> String? {
        guard let person else { return nil }
        let cleaned = normalizeWhitespace(person)
        guard !cleaned.isEmpty else { return nil }

        return cleaned
            .split(separator: " ")
            .map { formatNameFragment(String($0)) }
            .joined(separator: " ")
    }

    static func formattedNote(_ note: String?) -> String? {
        guard let note else { return nil }
        let cleaned = normalizeWhitespace(note)
        guard !cleaned.isEmpty else { return nil }

        guard let first = cleaned.first else { return cleaned }
        return String(first).uppercased() + cleaned.dropFirst()
    }

    private static func formatWord(_ word: String, isFirst: Bool, isLast: Bool) -> String {
        let parts = splitPunctuation(word)
        let core = parts.core
        guard !core.isEmpty else { return word }

        if let special = specialCasing[core.lowercased()] {
            return parts.leading + special + parts.trailing
        }

        if core.contains("/") || core.contains("@") || core.contains("#") || core.rangeOfCharacter(from: .decimalDigits) != nil {
            return word
        }

        if isMixedCase(core) || isAllUppercase(core) {
            return word
        }

        let lower = core.lowercased()
        if !isFirst, !isLast, lowercasedWords.contains(lower) {
            return parts.leading + lower + parts.trailing
        }

        return parts.leading + titleCaseToken(core) + parts.trailing
    }

    private static func formatNameFragment(_ fragment: String) -> String {
        let parts = splitPunctuation(fragment)
        guard !parts.core.isEmpty else { return fragment }
        return parts.leading + titleCaseToken(parts.core) + parts.trailing
    }

    private static func titleCaseToken(_ token: String) -> String {
        token
            .split(separator: "-", omittingEmptySubsequences: false)
            .map { hyphenPart in
                hyphenPart
                    .split(separator: "'", omittingEmptySubsequences: false)
                    .enumerated()
                    .map { index, apostrophePart in
                        guard let first = apostrophePart.first else { return "" }
                        let lower = apostrophePart.lowercased()
                        if index > 0, lowercaseApostropheSuffixes.contains(lower) {
                            return lower
                        }
                        return String(first).uppercased() + apostrophePart.dropFirst().lowercased()
                    }
                    .joined(separator: "'")
            }
            .joined(separator: "-")
    }

    private static func splitPunctuation(_ word: String) -> (leading: String, core: String, trailing: String) {
        let scalars = Array(word.unicodeScalars)
        var start = 0
        var end = scalars.count

        while start < end, !CharacterSet.alphanumerics.contains(scalars[start]) {
            start += 1
        }
        while end > start, !CharacterSet.alphanumerics.contains(scalars[end - 1]) {
            end -= 1
        }

        let leading = String(String.UnicodeScalarView(scalars[0..<start]))
        let core = String(String.UnicodeScalarView(scalars[start..<end]))
        let trailing = String(String.UnicodeScalarView(scalars[end..<scalars.count]))
        return (leading, core, trailing)
    }

    private static func normalizeWhitespace(_ input: String) -> String {
        input
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isMixedCase(_ token: String) -> Bool {
        token.rangeOfCharacter(from: .uppercaseLetters) != nil
            && token.rangeOfCharacter(from: .lowercaseLetters) != nil
    }

    private static func isAllUppercase(_ token: String) -> Bool {
        guard token.rangeOfCharacter(from: .lowercaseLetters) == nil else { return false }
        return token.rangeOfCharacter(from: .uppercaseLetters) != nil
    }
}
