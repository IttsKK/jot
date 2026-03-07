import Foundation

/// Tracks whether a meeting is currently active and provides meeting-aware capture helpers.
@MainActor
final class MeetingSession: ObservableObject {
    @Published private(set) var activeMeeting: Meeting?

    private let database: DatabaseManager

    init(database: DatabaseManager) {
        self.database = database
        // Restore any meeting that was active when the app was last quit
        activeMeeting = try? database.fetchActiveMeeting()
    }

    var isInMeeting: Bool {
        activeMeeting != nil
    }

    var meetingAttendeeList: [String] {
        activeMeeting?.attendeeList ?? []
    }

    var meetingSummary: String? {
        activeMeeting?.summary
    }

    func startMeeting(title: String, attendees: String?) throws {
        // End any currently active meeting first
        if let current = activeMeeting {
            try database.endMeeting(id: current.id)
        }
        let meeting = try database.createMeeting(title: title, attendees: attendees)
        activeMeeting = meeting
    }

    func updateActiveMeetingSummary(_ summary: String?) throws {
        guard var meeting = activeMeeting else { return }
        meeting.summary = summary
        try database.updateMeeting(meeting)
        activeMeeting = meeting
    }

    func endCurrentMeeting(summary: String? = nil) throws {
        guard let meeting = activeMeeting else { return }
        try database.endMeeting(id: meeting.id, summary: summary)
        activeMeeting = nil
    }
}
