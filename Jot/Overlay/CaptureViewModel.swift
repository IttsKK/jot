import CoreGraphics
import Foundation

@MainActor
final class CaptureViewModel: ObservableObject {
    @Published var input: String = ""
    @Published var focusNonce: UUID = UUID()
    @Published private(set) var panelHeight: CGFloat = 66
    @Published private(set) var parsed: ParsedTask = ParsedTask(rawInput: "", title: "", type: .task, queue: .work, person: nil, dueDate: nil, note: nil)
    @Published private(set) var activeCommand: InputCommand? = nil
    @Published private(set) var lockedQueue: TaskQueue? = nil
    @Published private(set) var showCommandSuggestions: Bool = false
    @Published var addToToday: Bool = false {
        didSet { refreshPanelHeight() }
    }

    let database: DatabaseManager
    let settings: SettingsStore
    let meetingSession: MeetingSession
    private var commandSuggestionsForced = false

    private var defaultCaptureQueue: TaskQueue {
        meetingSession.isInMeeting ? .thought : settings.defaultQueue
    }

    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isTypingCommandPrefix: Bool {
        guard !trimmedInput.isEmpty else { return false }
        guard trimmedInput.first == "/" else { return false }
        return !trimmedInput.contains(where: \.isWhitespace)
    }

    init(database: DatabaseManager, settings: SettingsStore, meetingSession: MeetingSession) {
        self.database = database
        self.settings = settings
        self.meetingSession = meetingSession
    }

    var showChips: Bool {
        guard activeCommand == nil else { return false }
        if addToToday { return true }
        if isTypingCommandPrefix { return false }

        if lockedQueue != nil {
            return true
        }

        return !trimmedInput.isEmpty
    }

    func updateParse() {
        if consumeNextCommand() { return }

        if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let queue = lockedQueue ?? defaultCaptureQueue
            let type: ParsedTaskType = queue == .thought ? .thought : .task
            parsed = ParsedTask(rawInput: "", title: "", type: type, queue: queue, person: nil, dueDate: nil, note: nil)
            refreshCommandSuggestionVisibility()
            refreshPanelHeight()
            return
        }

        if activeCommand != nil {
            let title = input.trimmingCharacters(in: .whitespacesAndNewlines)
            parsed = ParsedTask(rawInput: input, title: title, type: .task, queue: settings.defaultQueue, person: nil, dueDate: nil, note: nil)
            refreshCommandSuggestionVisibility()
            refreshPanelHeight()
            return
        }

        parsed = TaskParser.parse(input)

        if let q = lockedQueue {
            parsed.queue = q
            if q == .thought { parsed.type = .thought }
        }
        refreshCommandSuggestionVisibility()
        refreshPanelHeight()
    }

    /// Strips a single leading slash command and records it. Returns `true` when consumed
    /// so the caller can bail early — `updateParse` will fire again after `input` changes.
    @discardableResult
    private func consumeNextCommand() -> Bool {
        if let consumed = consumeExecutedLeadingCommand(from: input) {
            input = InputCommandParser.expandedRemainder(for: consumed.command, remainder: consumed.remainder)
            switch consumed.command.kind {
            case let .queue(queue):
                lockedQueue = queue
            case .today:
                addToToday = true
            case .meetingStart, .meetingEnd, .meetingSummary:
                activeCommand = consumed.command
            }
            commandSuggestionsForced = false
            refreshCommandSuggestionVisibility()
            refreshPanelHeight()
            return true
        }
        return false
    }

    private func consumeExecutedLeadingCommand(from input: String) -> ConsumedInputCommand? {
        let trimmedLeading = input.drop { $0.isWhitespace }
        guard !trimmedLeading.isEmpty, trimmedLeading.first == "/" else { return nil }

        guard let tokenEnd = trimmedLeading.firstIndex(where: \.isWhitespace) else {
            return nil
        }

        let token = trimmedLeading[..<tokenEnd]
        guard !token.isEmpty else { return nil }

        return InputCommandParser.consumeLeadingCommand(from: String(trimmedLeading))
    }

    func save() throws {
        switch activeCommand?.kind {
        case .meetingStart:
            let draft = MeetingDraftParser.parse(input)
            guard !draft.title.isEmpty else { return }
            try meetingSession.startMeeting(title: draft.title, attendees: draft.person)
            clear()
            return
        case .meetingEnd:
            let summary = TaskTextFormatter.formattedNote(input)
            try meetingSession.endCurrentMeeting(summary: summary ?? meetingSession.meetingSummary)
            clear()
            return
        case .meetingSummary:
            let summary = TaskTextFormatter.formattedNote(input)
            guard meetingSession.isInMeeting else { return }
            try meetingSession.updateActiveMeetingSummary(summary)
            clear()
            return
        case .some(.queue), .some(.today), .none:
            break
        }

        let raw = parsed.title.isEmpty ? TaskParser.parse(input) : parsed
        var effective = raw
        if let q = lockedQueue {
            effective.queue = q
            if q == .thought { effective.type = .thought }
        } else if shouldDefaultToNoteCapture(for: raw) {
            effective.queue = .thought
            effective.type = .thought
        }

        let title = TaskTextFormatter.formattedTitle(effective.title)
        guard !title.isEmpty else { return }

        let meetingId = meetingSession.activeMeeting?.id

        var person = TaskTextFormatter.formattedPerson(effective.person)
        if person == nil && effective.queue == .reachOut && meetingSession.isInMeeting {
            person = meetingSession.meetingAttendeeList.first
        }

        let dailyFocusDate = addToToday ? DatabaseManager.dayKey(for: .now) : nil

        if effective.queue == .thought, let meetingId {
            try database.captureMeetingNote(
                rawInput: input,
                content: title,
                meetingId: meetingId
            )
        } else {
            try database.createTask(
                rawInput: input,
                title: title,
                queue: effective.queue,
                person: person,
                dueDate: effective.dueDate,
                note: TaskTextFormatter.formattedNote(effective.note),
                meetingId: meetingId,
                dailyFocusDate: dailyFocusDate
            )
        }
        clear()
    }

    func clear() {
        input = ""
        activeCommand = nil
        lockedQueue = nil
        commandSuggestionsForced = false
        showCommandSuggestions = false
        addToToday = false
        parsed = ParsedTask(rawInput: "", title: "", type: .task, queue: settings.defaultQueue, person: nil, dueDate: nil, note: nil)
        refreshPanelHeight()
    }

    func clearActiveCommand() {
        activeCommand = nil
        refreshPanelHeight()
    }

    func clearLockedQueue() {
        lockedQueue = nil
        refreshPanelHeight()
    }

    func clearAddToToday() {
        addToToday = false
        refreshPanelHeight()
    }

    func selectCommand(_ command: InputCommand, remainder: String) {
        switch command.kind {
        case let .queue(queue):
            lockedQueue = queue
        case .today:
            addToToday = true
        case .meetingStart, .meetingEnd, .meetingSummary:
            activeCommand = command
        }
        input = InputCommandParser.expandedRemainder(for: command, remainder: remainder)
        updateParse()
    }

    func requestFocus() {
        focusNonce = UUID()
    }

    func revealCommandSuggestions() -> Bool {
        guard activeCommand == nil else { return false }
        let suggestions = InputCommandParser.suggestedCommands(for: input)
        guard !suggestions.isEmpty else { return false }
        commandSuggestionsForced = true
        refreshCommandSuggestionVisibility()
        refreshPanelHeight()
        return showCommandSuggestions
    }

    func refreshForSettingsChange() {
        if settings.quickCaptureCommandPreviewEnabled {
            commandSuggestionsForced = false
        }
        refreshCommandSuggestionVisibility()
        refreshPanelHeight()
    }

    private func refreshPanelHeight() {
        var h: CGFloat = 66
        if meetingSession.isInMeeting { h += 32 }

        if activeCommand == nil {
            let suggestions = InputCommandParser.suggestedCommands(for: input)
            if showCommandSuggestions, !suggestions.isEmpty {
                h += CGFloat(suggestions.count) * 28 + 32
            } else if showChips {
                h += 40
            }
        }

        panelHeight = h
    }

    private func refreshCommandSuggestionVisibility() {
        let suggestions = InputCommandParser.suggestedCommands(for: input)
        guard activeCommand == nil, !suggestions.isEmpty else {
            commandSuggestionsForced = false
            showCommandSuggestions = false
            return
        }

        if settings.quickCaptureCommandPreviewEnabled {
            showCommandSuggestions = true
        } else {
            showCommandSuggestions = commandSuggestionsForced
        }
    }

    private func shouldDefaultToNoteCapture(for parsed: ParsedTask) -> Bool {
        guard defaultCaptureQueue == .thought else { return false }
        guard parsed.queue == .work, parsed.type == .task else { return false }
        return input.range(of: #"(?:^|\s)/(?:w|r|t)(?=\s|$)"#, options: .regularExpression) == nil
    }
}
