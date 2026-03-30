#if canImport(XCTest)
import AppKit
import XCTest
@testable import Jot

@MainActor
final class CaptureViewModelTests: XCTestCase {
    private var defaultsSuiteName: String!

    override func tearDown() {
        if let defaultsSuiteName {
            UserDefaults(suiteName: defaultsSuiteName)?.removePersistentDomain(forName: defaultsSuiteName)
        }
        defaultsSuiteName = nil
        super.tearDown()
    }

    func testCommandPrefixDoesNotExecuteWithoutTrailingSpace() throws {
        let viewModel = try makeViewModel()

        viewModel.input = "/f"
        viewModel.updateParse()

        XCTAssertNil(viewModel.lockedQueue)
        XCTAssertNil(viewModel.activeCommand)
        XCTAssertFalse(viewModel.showChips)
        XCTAssertEqual(viewModel.input, "/f")

        viewModel.input = "/meeting"
        viewModel.updateParse()

        XCTAssertNil(viewModel.lockedQueue)
        XCTAssertNil(viewModel.activeCommand)
        XCTAssertFalse(viewModel.showChips)
        XCTAssertEqual(viewModel.input, "/meeting")
    }

    func testExecutedQueueCommandShowsLockedQueuePillState() throws {
        let viewModel = try makeViewModel()

        viewModel.input = "/f "
        viewModel.updateParse()

        XCTAssertEqual(viewModel.lockedQueue, .reachOut)
        XCTAssertNil(viewModel.activeCommand)
        XCTAssertTrue(viewModel.showChips)
        XCTAssertEqual(viewModel.input, "")
    }

    func testTodayCommandPreservesDefaultThoughtQueueWhileTyping() throws {
        let viewModel = try makeViewModel()

        viewModel.input = "/t "
        viewModel.updateParse()

        XCTAssertTrue(viewModel.addToToday)
        XCTAssertEqual(viewModel.parsed.queue, .thought)
        XCTAssertEqual(viewModel.parsed.type, .thought)

        viewModel.input = "capture this idea"
        viewModel.updateParse()

        XCTAssertTrue(viewModel.addToToday)
        XCTAssertEqual(viewModel.parsed.queue, .thought)
        XCTAssertEqual(viewModel.parsed.type, .thought)
    }

    func testExecutedMeetingCommandDisablesTaskParsingAndChips() throws {
        let viewModel = try makeViewModel()

        viewModel.input = "/meeting "
        viewModel.updateParse()

        XCTAssertEqual(viewModel.activeCommand?.kind, .meetingStart)
        XCTAssertNil(viewModel.lockedQueue)
        XCTAssertFalse(viewModel.showChips)
        XCTAssertEqual(viewModel.input, "")

        viewModel.input = "Tyler tomorrow"
        viewModel.updateParse()

        XCTAssertEqual(viewModel.activeCommand?.kind, .meetingStart)
        XCTAssertEqual(viewModel.parsed.title, "Tyler tomorrow")
        XCTAssertNil(viewModel.parsed.dueDate)
        XCTAssertEqual(viewModel.parsed.queue, .thought)
        XCTAssertFalse(viewModel.showChips)
    }

    func testDefaultCaptureSavesThoughtWhenNoQueueIsSpecified() throws {
        let viewModel = try makeViewModel()

        viewModel.input = "capture this idea"
        viewModel.updateParse()
        try viewModel.save()

        let thoughts = try viewModel.database.fetchThoughts()
        XCTAssertEqual(thoughts.count, 1)
        XCTAssertEqual(thoughts.first?.queue, .thought)
        XCTAssertEqual(thoughts.first?.title, "Capture This Idea")
    }

    func testDefaultThoughtCaptureKeepsAboutClauseInTitle() throws {
        let viewModel = try makeViewModel()

        viewModel.input = "brainstorm about launch copy"
        viewModel.updateParse()
        try viewModel.save()

        let thoughts = try viewModel.database.fetchThoughts()
        XCTAssertEqual(thoughts.count, 1)
        XCTAssertEqual(thoughts.first?.title, "Brainstorm About Launch Copy")
        XCTAssertNil(thoughts.first?.note)
    }

    func testMeetingNoteCaptureAppendsIntoSingleThought() throws {
        let viewModel = try makeViewModel()
        try viewModel.meetingSession.startMeeting(title: "Roadmap", attendees: nil)

        viewModel.input = "first note"
        viewModel.updateParse()
        try viewModel.save()

        viewModel.input = "second note"
        viewModel.updateParse()
        try viewModel.save()

        let thoughts = try viewModel.database.fetchThoughts()
        XCTAssertEqual(thoughts.count, 1)
        XCTAssertEqual(thoughts.first?.queue, .thought)
        XCTAssertEqual(thoughts.first?.meetingId, viewModel.meetingSession.activeMeeting?.id)
        XCTAssertEqual(thoughts.first?.title, "First Note\n\nSecond Note")
    }

    private func makeViewModel() throws -> CaptureViewModel {
        defaultsSuiteName = "CaptureViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        _ = NSApplication.shared
        let database = try DatabaseManager(inMemory: true)
        let settings = SettingsStore(defaults: defaults)
        let meetingSession = MeetingSession(database: database)
        return CaptureViewModel(database: database, settings: settings, meetingSession: meetingSession)
    }
}
#endif
