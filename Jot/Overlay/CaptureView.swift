import SwiftUI

struct CaptureView: View {
    @ObservedObject var viewModel: CaptureViewModel
    @ObservedObject var settings: SettingsStore
    var onDismiss: () -> Void

    @FocusState private var focused: Bool
    @State private var commandSelectionIndex = 0

    private var isInMeeting: Bool { viewModel.meetingSession.isInMeeting }
    private var meetingTitle: String { viewModel.meetingSession.activeMeeting?.title ?? "" }
    private var activeCommand: InputCommand? { viewModel.activeCommand }
    private var isThought: Bool { viewModel.lockedQueue == .thought || viewModel.parsed.queue == .thought }
    private var hasLockedMode: Bool { viewModel.lockedQueue != nil }
    private var commandSuggestions: [InputCommand] { InputCommandParser.suggestedCommands(for: viewModel.input) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isInMeeting ? Color.purple.opacity(0.35) : Color.white.opacity(0.18), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 12) {
                if isInMeeting {
                    meetingBanner
                }

                HStack(spacing: 10) {
                    if let activeCommand {
                        commandPill(activeCommand)
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    }

                    TextField(capturePrompt, text: $viewModel.input)
                        .textFieldStyle(.plain)
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .focused($focused)
                        .onChange(of: viewModel.input) { _, _ in
                            viewModel.updateParse()
                        }
                        .onSubmit {
                            try? viewModel.save()
                            onDismiss()
                        }
                }

                if viewModel.showCommandSuggestions {
                    commandSuggestionsPanel
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                }

                if viewModel.showChips {
                    chipRow
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
        .onTapGesture {
            focused = true
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.18), value: activeCommand?.id)
        .animation(.easeInOut(duration: 0.18), value: viewModel.showCommandSuggestions)
        .animation(.easeInOut(duration: 0.18), value: viewModel.showChips)
        .animation(.easeInOut(duration: 0.18), value: viewModel.addToToday)
        .animation(.easeInOut(duration: 0.18), value: isInMeeting)
        .onAppear {
            viewModel.updateParse()
            requestFocusSoon()
        }
        .onChange(of: viewModel.focusNonce) { _, _ in
            requestFocusSoon()
        }
        .onChange(of: settings.quickCaptureCommandPreviewEnabled) { _, _ in
            viewModel.refreshForSettingsChange()
        }
        .onChange(of: commandSuggestions.map(\.id)) { _, _ in
            if commandSuggestions.isEmpty {
                commandSelectionIndex = 0
            } else {
                commandSelectionIndex = min(commandSelectionIndex, commandSuggestions.count - 1)
            }
        }
        .background(EscapeKeyHandler(onEscape: {
            viewModel.clear()
            onDismiss()
        }, onDeleteBackward: {
            guard focused else { return false }
            guard viewModel.input.isEmpty else { return false }
            if viewModel.activeCommand != nil {
                viewModel.clearActiveCommand()
                return true
            }
            if viewModel.lockedQueue != nil {
                viewModel.clearLockedQueue()
                return true
            }
            if viewModel.addToToday {
                viewModel.clearAddToToday()
                return true
            }
            return false
        }, onArrowUp: {
            handleCommandSuggestionMove(up: true)
        }, onArrowDown: {
            handleCommandSuggestionMove(up: false)
        }, onEnter: {
            handleCommandSuggestionEnter()
        }, onTab: {
            viewModel.revealCommandSuggestions()
        }))
    }

    private var capturePrompt: String {
        if let activeCommand {
            return activeCommand.prompt
        }
        if isInMeeting { return "Note, task, follow-up..." }
        if let q = viewModel.lockedQueue {
            switch q {
            case .work: return "Type a work task..."
            case .reachOut: return "Who do you need to follow up with?"
            case .thought: return "Type a note..."
            }
        }
        return "Type a task..."
    }

    private var meetingBanner: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.red)
                .frame(width: 7, height: 7)
            Text(meetingTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.purple.opacity(0.9))
            Spacer()
        }
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            if viewModel.addToToday {
                todayToggle
            }

            if isThought {
                modeChip("Note", color: .indigo, isForced: viewModel.lockedQueue == .thought)
            } else {
                modeChip("Queue: \(viewModel.parsed.queue.displayName)",
                         color: queueColor(viewModel.parsed.queue),
                         isForced: hasLockedMode)
                if let date = viewModel.parsed.dueDate {
                    chip(relativeDate(date), color: .pink)
                }
                if let note = viewModel.parsed.note, !note.isEmpty {
                    chip("Note", color: .teal).help(note)
                }
            }
            Spacer()
        }
    }

    private var todayToggle: some View {
        Button {
            viewModel.addToToday.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: viewModel.addToToday ? "sun.max.fill" : "sun.max")
                    .font(.system(size: 11, weight: .bold))
                Text("Today")
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(Capsule().fill(Color.orange.opacity(viewModel.addToToday ? 0.28 : 0.12)))
            .overlay(Capsule().stroke(Color.orange.opacity(viewModel.addToToday ? 0.6 : 0.25), lineWidth: viewModel.addToToday ? 1.5 : 1))
            .foregroundStyle(Color.orange.opacity(viewModel.addToToday ? 0.95 : 0.6))
        }
        .buttonStyle(.plain)
    }

    private func commandPill(_ command: InputCommand) -> some View {
        HStack(spacing: 6) {
            Image(systemName: commandIcon(for: command))
                .font(.system(size: 12, weight: .bold))
            Text(command.label)
                .font(.system(size: 13, weight: .bold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(commandColor(for: command).opacity(0.24)))
        .overlay(Capsule().stroke(commandColor(for: command).opacity(0.58), lineWidth: 1.6))
        .foregroundStyle(commandColor(for: command).opacity(0.95))
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(
                Capsule().fill(color.opacity(0.18))
            )
            .overlay(
                Capsule().stroke(color.opacity(0.35), lineWidth: 1)
            )
    }

    private func modeChip(_ text: String, color: Color, isForced: Bool) -> some View {
        HStack(spacing: 4) {
            if isForced {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
        .background(Capsule().fill(color.opacity(isForced ? 0.28 : 0.18)))
        .overlay(Capsule().stroke(color.opacity(isForced ? 0.6 : 0.35), lineWidth: isForced ? 1.5 : 1))
        .foregroundStyle(color.opacity(0.95))
    }

    private var commandSuggestionsPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(commandSuggestions.enumerated()), id: \.element.id) { index, command in
                HStack(spacing: 8) {
                    Text(command.trigger)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 76, alignment: .leading)
                    Text(command.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(command.prompt)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(index == commandSelectionIndex ? Color.accentColor.opacity(0.16) : Color.clear)
                )
                .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.thinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.14), lineWidth: 1))
        )
    }

    private func handleCommandSuggestionMove(up: Bool) -> Bool {
        guard viewModel.showCommandSuggestions, activeCommand == nil, !commandSuggestions.isEmpty else { return false }
        let count = commandSuggestions.count
        if up {
            commandSelectionIndex = (commandSelectionIndex - 1 + count) % count
        } else {
            commandSelectionIndex = (commandSelectionIndex + 1) % count
        }
        return true
    }

    private func handleCommandSuggestionEnter() -> Bool {
        guard viewModel.showCommandSuggestions, activeCommand == nil, !commandSuggestions.isEmpty else { return false }
        let index = min(max(commandSelectionIndex, 0), commandSuggestions.count - 1)
        let command = commandSuggestions[index]
        applySuggestedCommand(command)
        return true
    }

    private func applySuggestedCommand(_ command: InputCommand) {
        let trimmedLeading = viewModel.input.drop { $0.isWhitespace }
        let tokenEnd = trimmedLeading.firstIndex(where: \.isWhitespace) ?? trimmedLeading.endIndex
        let remainder = String(trimmedLeading[tokenEnd...]).trimmingCharacters(in: .whitespaces)
        viewModel.selectCommand(command, remainder: remainder)
        commandSelectionIndex = 0
    }

    private func queueColor(_ queue: TaskQueue) -> Color {
        switch queue {
        case .work: return .orange
        case .reachOut: return .blue
        case .thought: return .indigo
        }
    }

    private func commandColor(for command: InputCommand) -> Color {
        switch command.kind {
        case let .queue(queue):
            return queueColor(queue)
        case .meetingStart, .meetingEnd, .meetingSummary:
            return .purple
        case .today:
            return .orange
        }
    }

    private func commandIcon(for command: InputCommand) -> String {
        switch command.kind {
        case let .queue(queue):
            switch queue {
            case .work: return "checkmark.square.fill"
            case .reachOut: return "arrowshape.turn.up.right.fill"
            case .thought: return "brain.head.profile"
            }
        case .meetingStart:
            return "video.fill"
        case .meetingEnd:
            return "record.circle"
        case .meetingSummary:
            return "text.bubble"
        case .today:
            return "sun.max.fill"
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: .now)
        let startOfDueDay = calendar.startOfDay(for: date)
        let dayDelta = calendar.dateComponents([.day], from: startOfToday, to: startOfDueDay).day ?? 0

        let dayText: String
        switch dayDelta {
        case 0:
            dayText = "today"
        case 1:
            dayText = "tomorrow"
        case -1:
            dayText = "yesterday"
        case 2...6:
            dayText = shortWeekdayFormatter.string(from: date)
        default:
            dayText = shortDateFormatter.string(from: date)
        }

        if hasExplicitDueTime(date) {
            return "\(dayText) \(shortTimeFormatter.string(from: date))"
        }
        return dayText
    }

    private func hasExplicitDueTime(_ date: Date) -> Bool {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        if hour == 0 && minute == 0 {
            return false
        }
        return !(hour == TaskParser.defaultDueHour && minute == TaskParser.defaultDueMinute)
    }

    private var shortDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }

    private var shortWeekdayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }

    private var shortTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }

    private func requestFocusSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            focused = true
        }
    }
}

private struct EscapeKeyHandler: NSViewRepresentable {
    var onEscape: () -> Void
    var onDeleteBackward: () -> Bool
    var onArrowUp: () -> Bool
    var onArrowDown: () -> Bool
    var onEnter: () -> Bool
    var onTab: () -> Bool

    func makeNSView(context: Context) -> NSView {
        let view = KeyHandlerView()
        view.onEscape = onEscape
        view.onDeleteBackward = onDeleteBackward
        view.onArrowUp = onArrowUp
        view.onArrowDown = onArrowDown
        view.onEnter = onEnter
        view.onTab = onTab
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? KeyHandlerView)?.onEscape = onEscape
        (nsView as? KeyHandlerView)?.onDeleteBackward = onDeleteBackward
        (nsView as? KeyHandlerView)?.onArrowUp = onArrowUp
        (nsView as? KeyHandlerView)?.onArrowDown = onArrowDown
        (nsView as? KeyHandlerView)?.onEnter = onEnter
        (nsView as? KeyHandlerView)?.onTab = onTab
    }
}

private final class KeyHandlerView: NSView {
    var onEscape: (() -> Void)?
    var onDeleteBackward: (() -> Bool)?
    var onArrowUp: (() -> Bool)?
    var onArrowDown: (() -> Bool)?
    var onEnter: (() -> Bool)?
    var onTab: (() -> Bool)?
    private var keyMonitor: Any?

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        guard window != nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {
                self.onEscape?()
                return nil
            }
            if event.keyCode == 51, self.onDeleteBackward?() == true {
                return nil
            }
            if event.keyCode == 126, self.onArrowUp?() == true {
                return nil
            }
            if event.keyCode == 125, self.onArrowDown?() == true {
                return nil
            }
            if event.keyCode == 36, self.onEnter?() == true {
                return nil
            }
            if event.keyCode == 48, self.onTab?() == true {
                return nil
            }
            return event
        }
    }
}
