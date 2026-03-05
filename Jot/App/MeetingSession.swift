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

    func startMeeting(title: String, attendees: String?) throws {
        // End any currently active meeting first
        if let current = activeMeeting {
            try database.endMeeting(id: current.id)
        }
        let meeting = try database.createMeeting(title: title, attendees: attendees)
        activeMeeting = meeting
    }

    func endCurrentMeeting() throws {
        guard let meeting = activeMeeting else { return }
        try database.endMeeting(id: meeting.id)
        activeMeeting = nil
    }
}
