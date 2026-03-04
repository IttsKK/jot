import Foundation

enum DateCodec {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(from string: String?) -> Date? {
        guard let string else { return nil }
        if let date = formatter.date(from: string) {
            return date
        }
        return ISO8601DateFormatter().date(from: string)
    }
}
