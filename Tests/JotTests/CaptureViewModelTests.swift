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
        XCTAssertEqual(viewModel.parsed.queue, .work)
        XCTAssertFalse(viewModel.showChips)
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
