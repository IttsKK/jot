import SwiftUI

struct MainTaskListView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var meetingSession: MeetingSession
    @AppStorage(UserDefaultKeys.mainSidebarWidth) private var storedSidebarWidth: Double = 220
    @AppStorage(UserDefaultKeys.mainSidebarCollapsed) private var isSidebarCollapsed = false
    @StateObject private var viewModel: TaskListViewModel
    @State private var completedExpanded = false
    @State private var composer: TaskComposerState
    @State private var showDeleteConfirmation = false
    @State private var isComposerInputHovering = false
    @State private var selectedMetadataField: MetadataField = .main
    @State private var showStartMeetingSheet = false
    @State private var showEndMeetingSheet = false
    @State private var meetingDraftInput: String = ""
    @State private var meetingSummaryInput: String = ""
    @State private var meetingSummaryDraft: String = ""
    @State private var taskDetailDraft: TaskDetailDraft? = nil
    @State private var pendingTaskDetailSyncID: String? = nil
    @State private var selectedNoteID: String? = nil
    @State private var thoughtEditorText: String = ""
    @State private var metadataEditorInput: String = ""
    @State private var sidebarDragStartWidth: CGFloat?
    @FocusState private var focusedComposerField: ComposerField?
    @FocusState private var focusedTaskDetailField: TaskDetailField?

    private enum ComposerField: Hashable {
        case main
    }

    private enum TaskDetailField: Hashable {
        case title
        case person
        case due
        case note
    }

    private enum MetadataField: Hashable {
        case main
        case queue
        case due
        case note
        case status

        var title: String {
            switch self {
            case .main: return "Task"
            case .queue: return "Queue"
            case .due: return "Due Date"
            case .note: return "Note"
            case .status: return "Status"
            }
        }

        var placeholder: String {
            switch self {
            case .main: return "Type your task..."
            case .queue: return "work, follow up, or note"
            case .due: return "tomorrow at 12, in 12 hours, mar 5..."
            case .note: return "extra context..."
            case .status: return "active, done, archived"
            }
        }
    }

    init(database: DatabaseManager, settings: SettingsStore, meetingSession: MeetingSession) {
        self.settings = settings
        self.meetingSession = meetingSession
        _viewModel = StateObject(wrappedValue: TaskListViewModel(database: database))
        _composer = State(initialValue: TaskComposerState.capture(defaultQueue: settings.defaultQueue))
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: currentSidebarWidth)

            sidebarResizeHandle

            contentPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(backgroundLayer)
        .background(
            MainPromptKeyMonitor(
                onEscape: { handleEscape() },
                onFocusPrompt: { focusPrompt() },
                onTab: { reverse in cycleMetadataField(reverse: reverse) },
                onArrowUp: { handleListArrowUp() },
                onArrowDown: { handleListArrowDown() },
                onEnter: { handleListEnter() },
                onSpace: { handleListSpace() },
                onDelete: { handleListDelete() },
                onSelectAll: { handleSelectAll() }
            )
        )
        .background(keyboardShortcutButtons)
        .task {
            try? viewModel.refresh()
            syncTaskDetailDraftFromSelection(force: true)
            syncMeetingSummaryDraft()
        }
        .onChange(of: viewModel.tasks) { _, _ in
            viewModel.validateSelection()
            syncTaskDetailDraftFromSelection()
        }
        .onChange(of: viewModel.selectedTaskIDs) { _, _ in
            syncTaskDetailDraftFromSelection(force: true)
        }
        .onChange(of: viewModel.selectedItem) { _, newItem in
            viewModel.validateSelection()
            if !supportsNoteSelection(for: newItem) {
                closeThoughtEditor()
            } else if case .meeting(let meetingID) = newItem,
                      let selectedNote,
                      selectedNote.meetingId != meetingID {
                closeThoughtEditor()
            }
            if let queue = defaultComposerQueue(for: newItem) {
                composer.queue = queue
                composer.command = nil
                if selectedMetadataField == .queue || selectedMetadataField == .main {
                    syncMetadataEditorInputFromSelection()
                }
            }
            syncMeetingSummaryDraft()
        }
        .onChange(of: viewModel.meetings) { _, meetings in
            if case .meeting(let id) = viewModel.selectedItem {
                if !meetings.contains(where: { $0.id == id }) {
                    viewModel.selectedItem = .all
                }
            }
            syncMeetingSummaryDraft()
        }
        .onChange(of: viewModel.thoughts) { _, thoughts in
            if let selectedNoteID {
                if thoughts.first(where: { $0.id == selectedNoteID }) == nil {
                    self.selectedNoteID = nil
                    thoughtEditorText = ""
                }
            }
        }
        .sheet(isPresented: $showStartMeetingSheet) {
            startMeetingSheet
        }
        .sheet(isPresented: $showEndMeetingSheet) {
            endMeetingSheet
        }
        .alert("Delete \(viewModel.selectedTaskIDs.count) tasks?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) { viewModel.bulkDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }

    // Hidden buttons to register keyboard shortcuts
    private var keyboardShortcutButtons: some View {
        Group {
            Button("") { withAnimation(.easeInOut(duration: 0.15)) { viewModel.selectedItem = .all } }
                .keyboardShortcut("1", modifiers: .command)
            Button("") { withAnimation(.easeInOut(duration: 0.15)) { viewModel.selectedItem = .work } }
                .keyboardShortcut("2", modifiers: .command)
            Button("") { withAnimation(.easeInOut(duration: 0.15)) { viewModel.selectedItem = .followUp } }
                .keyboardShortcut("3", modifiers: .command)
            Button("") { withAnimation(.easeInOut(duration: 0.15)) { viewModel.selectedItem = .inbox } }
                .keyboardShortcut("4", modifiers: .command)
            Button("") { AppContext.shared.openDailyFocusWindow() }
                .keyboardShortcut("5", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    private var backgroundLayer: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(red: 0.08, green: 0.09, blue: 0.11), Color(red: 0.11, green: 0.12, blue: 0.15)]
                : [Color(red: 0.96, green: 0.97, blue: 0.99), Color(red: 0.91, green: 0.94, blue: 0.98)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private let sidebarMinWidth: CGFloat = 180
    private let sidebarMaxWidth: CGFloat = 340
    private let collapsedSidebarWidth: CGFloat = 56

    private var currentSidebarWidth: CGFloat {
        isSidebarCollapsed ? collapsedSidebarWidth : CGFloat(storedSidebarWidth)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if !isSidebarCollapsed {
                    Text("Jot")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        if !isSidebarCollapsed {
                            storedSidebarWidth = Double(currentSidebarWidth)
                        }
                        isSidebarCollapsed.toggle()
                    }
                } label: {
                    Image(systemName: isSidebarCollapsed ? "sidebar.left" : "sidebar.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help(isSidebarCollapsed ? "Expand Sidebar" : "Collapse Sidebar")
            }
            .padding(.horizontal, isSidebarCollapsed ? 10 : 16)
            .padding(.top, 16)
            .padding(.bottom, 4)

            if meetingSession.isInMeeting, let meeting = meetingSession.activeMeeting {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.selectedItem = .meeting(meeting.id)
                    }
                } label: {
                    if isSidebarCollapsed {
                        Circle().fill(.red).frame(width: 10, height: 10)
                            .frame(width: 36, height: 28)
                    } else {
                        HStack(spacing: 6) {
                            Circle().fill(.red).frame(width: 6, height: 6)
                            Text(meeting.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, isSidebarCollapsed ? 10 : 16)
                .padding(.bottom, 4)
                .help(meeting.title)
            }

            Spacer().frame(height: 12)

            // Queue section
            if !isSidebarCollapsed {
                sidebarSectionHeader("Queues")
            }
            sidebarRow(item: .all, icon: "tray.full", title: "All", color: .primary)
            sidebarRow(item: .work, icon: "checkmark.square", title: "Work", color: .orange)
            sidebarRow(item: .followUp, icon: "arrowshape.turn.up.right", title: "Follow Up", color: .blue)
            sidebarRow(item: .inbox, icon: "note.text", title: "Notes", color: .indigo)

            Spacer().frame(height: 20)

            // Meetings section
            HStack {
                if !isSidebarCollapsed {
                    sidebarSectionHeader("Meetings")
                    Spacer()
                }

                Button { openStartMeetingSheet() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, isSidebarCollapsed ? 18 : 16)
                .help("Start Meeting")
            }

            if viewModel.meetings.isEmpty {
                if !isSidebarCollapsed {
                    Text("No meetings yet")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
            } else {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(viewModel.meetings) { meeting in
                            sidebarMeetingRow(meeting)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }

            if viewModel.meetings.isEmpty {
                Spacer()
            }

            Divider().padding(.horizontal, 12)

            // Today Focus
            Button {
                AppContext.shared.openDailyFocusWindow()
            } label: {
                Group {
                    if isSidebarCollapsed {
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity)
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "sun.max.fill")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.orange)
                        Text("Today Focus")
                            .font(.system(size: 13, weight: .medium))
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, isSidebarCollapsed ? 0 : 12)
                .padding(.vertical, isSidebarCollapsed ? 10 : 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .help("Open Today Focus")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(sidebarBackgroundColor.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.18), value: isSidebarCollapsed)
    }

    private func sidebarSectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .kerning(0.8)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
    }

    private func sidebarRow(item: TaskListViewModel.SidebarItem, icon: String, title: String, color: Color) -> some View {
        let isSelected = viewModel.selectedItem == item
        let count = sidebarCount(for: item)

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                viewModel.selectedItem = item
            }
        } label: {
            Group {
                if isSidebarCollapsed {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : color == .primary ? .secondary : color)
                        .frame(maxWidth: .infinity)
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(isSelected ? .white : color == .primary ? .secondary : color)
                            .frame(width: 20)

                    Text(title)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? .white : .primary)

                        Spacer()

                        if count > 0 {
                            Text("\(count)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, isSidebarCollapsed ? 0 : 10)
            .padding(.vertical, isSidebarCollapsed ? 10 : 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .help(title)
    }

    private func sidebarMeetingRow(_ meeting: Meeting) -> some View {
        let isSelected = viewModel.selectedItem == .meeting(meeting.id)
        let count = viewModel.tasksForMeeting(meeting).count

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                viewModel.selectedItem = .meeting(meeting.id)
            }
        } label: {
            Group {
                if isSidebarCollapsed {
                    if meeting.isActive {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 10, height: 10)
                            .frame(maxWidth: .infinity)
                    } else {
                        Image(systemName: "doc.text")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(isSelected ? .white : .secondary)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    HStack(spacing: 10) {
                        if meeting.isActive {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                                .frame(width: 20)
                        } else {
                            Image(systemName: "doc.text")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(isSelected ? .white : .secondary)
                                .frame(width: 20)
                        }

                        Text(meeting.title)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? .white : .primary)
                            .lineLimit(1)

                        Spacer()

                        if count > 0 {
                            Text("\(count)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, isSidebarCollapsed ? 0 : 10)
            .padding(.vertical, isSidebarCollapsed ? 10 : 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .help(meeting.title)
        .contextMenu {
            if meeting.isActive {
                Button("End Meeting") {
                    try? meetingSession.endCurrentMeeting()
                }
            }
            Button(role: .destructive) {
                viewModel.deleteMeeting(meeting)
            } label: {
                Label("Delete Meeting", systemImage: "trash")
            }
        }
    }

    private func sidebarCount(for item: TaskListViewModel.SidebarItem) -> Int {
        switch item {
        case .all:
            return viewModel.tasks.filter { ($0.queue == .work || $0.queue == .reachOut) && $0.status == .active }.count
        case .work:
            return viewModel.tasks.filter { $0.queue == .work && $0.status == .active }.count
        case .followUp:
            return viewModel.tasks.filter { $0.queue == .reachOut && $0.status == .active }.count
        case .inbox:
            return viewModel.thoughts.count
        case .meeting(let id):
            return viewModel.tasks.filter { $0.meetingId == id }.count
        }
    }

    private var sidebarBackgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.09, green: 0.09, blue: 0.11)
            : Color(red: 0.93, green: 0.94, blue: 0.96)
    }

    private var sidebarResizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: isSidebarCollapsed ? 1 : 8)
            .overlay(alignment: .center) {
                Rectangle()
                    .fill(panelStrokeColor.opacity(isSidebarCollapsed ? 0.5 : 1))
                    .frame(width: 1)
            }
            .contentShape(Rectangle())
            .gesture(sidebarResizeGesture)
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
    }

    private var sidebarResizeGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if sidebarDragStartWidth == nil {
                    sidebarDragStartWidth = currentSidebarWidth
                    if isSidebarCollapsed {
                        isSidebarCollapsed = false
                        sidebarDragStartWidth = CGFloat(storedSidebarWidth)
                    }
                }

                let start = sidebarDragStartWidth ?? CGFloat(storedSidebarWidth)
                let proposed = min(max(start + value.translation.width, sidebarMinWidth), sidebarMaxWidth)
                storedSidebarWidth = Double(proposed)
            }
            .onEnded { _ in
                sidebarDragStartWidth = nil
            }
    }

    // MARK: - Content Panel

    private var contentPanel: some View {
        VStack(spacing: 12) {
            switch viewModel.selectedItem {
            case .meeting:
                meetingContent
            default:
                queueContent
            }
        }
        .padding(16)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: currentSelectedTask?.id)
    }

    // MARK: - Queue Content

    private var queueContent: some View {
        Group {
            if viewModel.selectedItem == .inbox {
                inboxPanel
            } else {
                if viewModel.visibleTasks.isEmpty {
                    emptyStatePanel
                } else {
                    if viewModel.isMultiSelect {
                        bulkActionsBar
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    taskListPanel
                }
            }

            if viewModel.selectedItem == .inbox, let thought = selectedNote {
                thoughtEditorPanel(thought)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if let task = currentSelectedTask {
                taskDetailsPanel(task: task)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                composerPanel
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    // MARK: - Meeting Content

    @ViewBuilder
    private var meetingContent: some View {
        if let meeting = viewModel.selectedMeeting {
            let meetingItems = viewModel.tasksForMeeting(meeting)
            if meeting.isActive {
                HStack {
                    Label("In Progress", systemImage: "record.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.red)
                    Spacer()
                    Button("End Meeting") {
                        openEndMeetingSheet()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.red.opacity(0.12)))
                    .overlay(Capsule().stroke(Color.red.opacity(0.25), lineWidth: 1))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(glassPanel(cornerRadius: 10))
            }

            meetingPanel(meeting, items: meetingItems)

            if let thought = selectedMeetingNote {
                thoughtEditorPanel(thought)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if let task = currentSelectedTask {
                taskDetailsPanel(task: task)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                composerPanel
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                Text("Meeting not found")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Start Meeting Sheet

    private var startMeetingSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Start Meeting")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("Use one flexible field: `Tyler`, `Product roadmap`, or `Product roadmap with Tyler`.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") {
                    showStartMeetingSheet = false
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Meeting")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                meetingInputField("Product roadmap with Tyler", text: $meetingDraftInput)
            }

            Text("Quick capture equivalent: `/m Product roadmap with Tyler`")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)

            HStack {
                Spacer()
                Button("Start") {
                    startMeeting()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.accentColor))
                .foregroundStyle(.white)
                .keyboardShortcut(.defaultAction)
                .disabled(meetingDraftInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 460)
        .background(backgroundLayer)
    }

    private var endMeetingSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("End Meeting")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("Add an optional summary before ending the meeting.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") {
                    showEndMeetingSheet = false
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Summary (Optional)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)

                TextEditor(text: $meetingSummaryInput)
                    .font(.system(size: 15, weight: .regular))
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(minHeight: 120)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.thinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(panelStrokeColor, lineWidth: 1)
                            )
                    )
            }

            HStack {
                Spacer()
                Button("End Meeting") {
                    endMeeting()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.red))
                .foregroundStyle(.white)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 460)
        .background(backgroundLayer)
    }

    private func openStartMeetingSheet() {
        meetingDraftInput = ""
        showStartMeetingSheet = true
    }

    private func openEndMeetingSheet() {
        meetingSummaryInput = meetingSession.meetingSummary ?? ""
        showEndMeetingSheet = true
    }

    private func startMeeting() {
        let draft = MeetingDraftParser.parse(meetingDraftInput)
        guard !draft.title.isEmpty else { return }

        try? meetingSession.startMeeting(title: draft.title, attendees: draft.person)
        if let active = meetingSession.activeMeeting {
            viewModel.selectedItem = .meeting(active.id)
        }
        showStartMeetingSheet = false
    }

    private func endMeeting() {
        let summary = TaskTextFormatter.formattedNote(meetingSummaryInput) ?? meetingSession.meetingSummary
        try? meetingSession.endCurrentMeeting(summary: summary)
        showEndMeetingSheet = false
    }

    private func meetingInputField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 16, weight: .medium, design: .rounded))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(panelStrokeColor, lineWidth: 1)
                    )
            )
    }

    // MARK: - Inbox Panel

    private var inboxPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(viewModel.thoughts.count) notes")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)

            if viewModel.thoughts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "note.text")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("Nothing in your inbox")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Use the composer below or /n in quick capture.")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(viewModel.thoughts) { thought in
                        thoughtRow(thought)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    }
                    .onMove(perform: viewModel.moveThought)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(glassPanel(cornerRadius: 16))
        .onTapGesture {
            guard selectedNoteID != nil else { return }
            closeThoughtEditor()
        }
    }

    private func thoughtRow(_ thought: Task) -> some View {
        let isSelected = selectedNoteID == thought.id
        return ThoughtRowView(
            thought: thought,
            isSelected: isSelected,
            onSelect: { openThoughtEditor(thought) },
            onDelete: { viewModel.delete(thought) }
        )
    }

    private var selectedNote: Task? {
        guard let selectedNoteID else { return nil }
        return viewModel.thoughts.first(where: { $0.id == selectedNoteID })
    }

    private var selectedMeetingNote: Task? {
        guard case .meeting(let meetingID) = viewModel.selectedItem,
              let note = selectedNote,
              note.meetingId == meetingID else { return nil }
        return note
    }

    private func thoughtEditorPanel(_ thought: Task) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("Editing Note")
                    .font(.system(size: 14, weight: .bold))

                Spacer()

                if let created = thought.createdAtValue {
                    Text(RelativeDateTimeFormatter().localizedString(for: created, relativeTo: .now))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.bottom, 16)

            TextEditor(text: $thoughtEditorText)
                .font(.system(size: 16, weight: .regular))
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(minHeight: 200)
                .padding(.bottom, 16)
                .onExitCommand {
                    closeThoughtEditor()
                }

            HStack {
                Button("Delete", role: .destructive) {
                    viewModel.delete(thought)
                    closeThoughtEditor()
                    thoughtEditorText = ""
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.red.opacity(0.8))

                Spacer()

                Button("Close") {
                    closeThoughtEditor()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    saveThoughtEditor(thought)
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.accentColor))
                .foregroundStyle(.white)
                .keyboardShortcut(.defaultAction)
                .disabled(thoughtEditorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(glassPanel(cornerRadius: 16))
        .onTapGesture { }
    }

    private func openThoughtEditor(_ thought: Task) {
        if selectedNoteID == thought.id {
            selectedNoteID = nil
            return
        }
        viewModel.clearSelection()
        thoughtEditorText = thought.title
        selectedNoteID = thought.id
    }

    private func saveThoughtEditor(_ thought: Task) {
        let trimmed = thoughtEditorText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.updateTask(
            id: thought.id,
            rawInput: trimmed,
            title: trimmed,
            queue: .thought,
            status: thought.status,
            person: nil,
            dueDate: nil,
            note: nil
        )
        closeThoughtEditor()
    }

    private func closeThoughtEditor() {
        selectedNoteID = nil
    }

    // MARK: - Task List

    private var taskListPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(viewModel.activeTasks.count) active")
                if viewModel.totalCompletedCount > 0 {
                    Text("•")
                    Text("\(viewModel.totalCompletedCount) completed")
                }
                Spacer()
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 12)

            List(selection: $viewModel.selectedTaskIDs) {
                Section {
                    ForEach(viewModel.activeTasks) { task in
                        TaskRowView(
                            task: task,
                            isSelected: viewModel.selectedTaskIDs.contains(task.id),
                            showQueueBadge: viewModel.selectedItem == .all,
                            onToggle: { viewModel.toggleDone(task) }
                        )
                        .tag(task.id)
                        .contextMenu {
                            Button("Edit") { beginEditing(task) }
                            Button("Add to Today List") { viewModel.addTaskToDailyFocus(task) }
                            Button("Snooze") { viewModel.snooze(task) }
                            Button("Delete", role: .destructive) { viewModel.delete(task) }
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    }
                    .onMove(perform: viewModel.moveActive)
                } header: {
                    sectionHeader("Active")
                }

                if !viewModel.recentlyCompletedTasks.isEmpty {
                    Section {
                        ForEach(viewModel.recentlyCompletedTasks) { task in
                            TaskRowView(
                                task: task,
                                isSelected: viewModel.selectedTaskIDs.contains(task.id),
                                showQueueBadge: viewModel.selectedItem == .all,
                                trailingActionTitle: "Undo",
                                onTrailingAction: { viewModel.toggleDone(task) },
                                onToggle: { viewModel.toggleDone(task) }
                            )
                            .tag(task.id)
                            .contextMenu {
                                Button("Edit") { beginEditing(task) }
                                Button("Add to Today List") { viewModel.addTaskToDailyFocus(task) }
                                Button("Delete", role: .destructive) { viewModel.delete(task) }
                            }
                            .opacity(0.72)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        }
                    } header: {
                        HStack {
                            sectionHeader("Just Completed")
                            Spacer()
                            Text("Undo for \(Int(TaskListViewModel.completionUndoWindow))s")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !viewModel.completedTasks.isEmpty {
                    Section {
                        if completedExpanded {
                            ForEach(viewModel.completedTasks) { task in
                                TaskRowView(
                                    task: task,
                                    isSelected: viewModel.selectedTaskIDs.contains(task.id),
                                    showQueueBadge: viewModel.selectedItem == .all,
                                    onToggle: { viewModel.toggleDone(task) }
                                )
                                .tag(task.id)
                                .contextMenu {
                                    Button("Edit") { beginEditing(task) }
                                    Button("Add to Today List") { viewModel.addTaskToDailyFocus(task) }
                                    Button("Delete", role: .destructive) { viewModel.delete(task) }
                                }
                                .opacity(0.62)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                            }
                        }
                    } header: {
                        HStack {
                            sectionHeader("Completed")
                            Spacer()
                            Button(completedExpanded ? "Hide" : "Show") {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    completedExpanded.toggle()
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        }
                    }
                }

            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .environment(\.defaultMinListRowHeight, 52)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(glassPanel(cornerRadius: 16))
    }

    private var emptyStatePanel: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 38))
                .foregroundStyle(.blue.opacity(0.75))

            Text("No tasks yet")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Text("Use the composer below to add your first task.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 430)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(glassPanel(cornerRadius: 16))
    }

    // MARK: - Composer

    private var composerPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(composer.isEditing ? "Editing Task" : "Quick Add")
                    .font(.system(size: 13, weight: .bold))

                if composer.isEditing {
                    Text("Draft mode: changes apply on Enter")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if composer.isEditing {
                    Button("Cancel Edit") {
                        startNewComposer()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 6) {
                Text("Editing \(selectedMetadataField.title)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                if composer.command?.kind == .meetingStart {
                    Text("meeting command active")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.purple.opacity(0.85))
                } else if composer.command?.kind == .meetingEnd {
                    Text("end meeting with summary")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.purple.opacity(0.85))
                } else if composer.command?.kind == .meetingSummary {
                    Text("set meeting summary")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.purple.opacity(0.85))
                } else if selectedMetadataField == .due {
                    Text("type naturally or use picker below")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                if selectedMetadataField == .main, let command = composer.command {
                    composerCommandPill(command)
                }

                TextField(composerInputPlaceholder, text: $metadataEditorInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .focused($focusedComposerField, equals: .main)
                    .onChange(of: metadataEditorInput) { _, _ in
                        applyMetadataEditorInput()
                    }
                    .onSubmit(submitComposer)
                    .onHover { hovering in
                        isComposerInputHovering = hovering
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(composerInputStrokeColor, lineWidth: composerInputStrokeWidth)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        focusedComposerField = .main
                    }
                    .animation(.easeOut(duration: 0.15), value: isComposerInputHovering)
                    .animation(.easeOut(duration: 0.15), value: composerInputIsFocused)
            )
            .shadow(
                color: Color.accentColor.opacity(composerInputIsFocused ? 0.18 : (isComposerInputHovering ? 0.08 : 0)),
                radius: composerInputIsFocused ? 10 : 6,
                y: composerInputIsFocused ? 2 : 1
            )

            if selectedMetadataField == .main, composer.command == nil, !composerCommandSuggestions.isEmpty {
                composerCommandSuggestionsPanel
            }

            HStack(spacing: 8) {
                if composer.command?.kind == .meetingStart {
                    Text("Enter a meeting draft like 'Tyler' or 'Product roadmap with Tyler'")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.purple.opacity(0.88))
                } else if composer.command?.kind == .meetingEnd {
                    Text("Add an optional summary, then press Return to end the meeting")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.purple.opacity(0.88))
                } else if composer.command?.kind == .meetingSummary {
                    Text("Update the meeting summary without ending it")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.purple.opacity(0.88))
                } else {
                    metadataCard(
                        text: "Queue: \(resolvedQueue.displayName)",
                        field: .queue,
                        color: queueColor(resolvedQueue)
                    )

                    metadataCard(
                        text: resolvedDueDate.map { TaskDueFormatter.compactLabel(for: $0) } ?? "Due Date",
                        field: .due,
                        color: .pink
                    )

                    metadataCard(
                        text: resolvedNote.map { "Note: \($0)" } ?? "Note",
                        field: .note,
                        color: .teal
                    )

                    if composer.isEditing {
                        metadataCard(
                            text: "Status: \(composer.status.rawValue.capitalized)",
                            field: .status,
                            color: composer.status == .done ? .green : (composer.status == .archived ? .gray : .indigo)
                        )
                    }
                }

                Spacer()
                Text("Tab: Next  Shift+Tab: Prev  Enter: Save  Esc: Focus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }

            if selectedMetadataField == .due,
               composer.command?.kind != .meetingStart,
               composer.command?.kind != .meetingEnd,
               composer.command?.kind != .meetingSummary {
                dueDateEditorPanel
            }
        }
        .onAppear {
            syncMetadataEditorInputFromSelection()
        }
        .padding(14)
        .background(glassPanel(cornerRadius: 16))
    }

    private var dueDateEditorPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label("Quick Suggestions", systemImage: "bolt.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear Date") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        composer.dueDate = nil
                        composer.dueText = ""
                        metadataEditorInput = ""
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.red)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    quickDateButton("Today", icon: "sun.max.fill")
                    quickDateButton("Tomorrow", icon: "moon.stars.fill")
                    quickDateButton("This Weekend", icon: "cup.and.saucer.fill")
                    quickDateButton("Next Week", icon: "calendar.badge.clock")
                    quickDateButton("In 2 weeks", icon: "clock.fill")
                }
            }

            Text("Tip: you can also type values like `3pm`, `tomorrow at 12`, or `in 12 hours`.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.thinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(panelStrokeColor, lineWidth: 1))
        )
    }

    private func quickDateButton(_ title: String, icon: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                metadataEditorInput = title.lowercased()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.secondary.opacity(0.1)))
            .overlay(Capsule().stroke(Color.secondary.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var currentSelectedTask: Task? {
        guard viewModel.selectedTaskIDs.count == 1, let id = viewModel.selectedTaskIDs.first else { return nil }
        switch viewModel.selectedItem {
        case .meeting:
            guard let meeting = viewModel.selectedMeeting else { return nil }
            return viewModel.tasksForMeeting(meeting).first(where: { $0.id == id && $0.queue != .thought })
        default:
            return viewModel.visibleTasks.first(where: { $0.id == id })
        }
    }

    // MARK: - Task Details Panel

    private func taskDetailsPanel(task: Task) -> some View {
        let titleBinding = taskDetailBinding(\.title, default: task.title)
        let queueBinding = taskDetailBinding(\.queue, default: task.queue)
        let statusBinding = taskDetailBinding(\.status, default: task.status)
        let personBinding = taskDetailBinding(\.person, default: task.person ?? "")
        let noteBinding = taskDetailBinding(\.note, default: task.note ?? "")
        let dueTextBinding = taskDetailBinding(\.dueText, default: task.dueDateValue.map(dueFieldFormatter.string(from:)) ?? "")
        let resolvedDueDate = resolvedTaskDetailDueDate(fallback: task.dueDateValue)
        let hasInvalidDueText = !dueTextBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && resolvedDueDate == nil
        let showPersonField = queueBinding.wrappedValue == .reachOut || !personBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Button(action: {
                    focusedTaskDetailField = nil
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        viewModel.clearSelection()
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)

                Text("Edit Task")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Revert") {
                    withAnimation {
                        resetTaskDetailDraft(from: task)
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        _ = saveTaskDetailEdits(closeAfterSaving: true)
                    }
                } label: {
                    Text("Save")
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.accentColor))
                .foregroundStyle(.white)
                .disabled(taskDetailDraft?.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true || hasInvalidDueText)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Task")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .kerning(0.5)

                TextField("Follow up with Chris about pricing", text: titleBinding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .focused($focusedTaskDetailField, equals: .title)
                    .onSubmit { _ = saveTaskDetailEdits(closeAfterSaving: true) }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.thinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(panelStrokeColor, lineWidth: 1)
                            )
                    )
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Queue")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                    Picker("Queue", selection: queueBinding) {
                        ForEach(TaskQueue.allCases, id: \.self) { queue in
                            Text(queue.displayName).tag(queue)
                        }
                    }
                    .pickerStyle(.menu)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Status")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                    Picker("Status", selection: statusBinding) {
                        ForEach(TaskStatus.allCases, id: \.self) { status in
                            Text(status.rawValue.capitalized).tag(status)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Spacer()
            }

            if showPersonField {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Person")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .kerning(0.5)

                    TextField("Chris", text: personBinding)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .medium))
                        .focused($focusedTaskDetailField, equals: .person)
                        .onSubmit { _ = saveTaskDetailEdits(closeAfterSaving: true) }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.thinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(panelStrokeColor, lineWidth: 1)
                                )
                        )
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("When")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .kerning(0.5)
                    Spacer()
                    if let resolvedDueDate {
                        Text(TaskDueFormatter.detailLabel(for: resolvedDueDate))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                TextField("tomorrow at 3, next week tuesday, mar 5 2pm", text: dueTextBinding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .medium))
                    .focused($focusedTaskDetailField, equals: .due)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.thinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(panelStrokeColor, lineWidth: 1)
                            )
                    )
                    .onChange(of: dueTextBinding.wrappedValue) { _, newValue in
                        updateTaskDetailDueText(newValue, fallback: task.dueDateValue)
                    }
                    .onSubmit { _ = saveTaskDetailEdits(closeAfterSaving: true) }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        taskDetailQuickDateButton("Today", phrase: "today", fallback: task.dueDateValue)
                        taskDetailQuickDateButton("Tomorrow", phrase: "tomorrow", fallback: task.dueDateValue)
                        taskDetailQuickDateButton("Next Week", phrase: "next week", fallback: task.dueDateValue)
                        taskDetailQuickDateButton("Next Tue", phrase: "next week tuesday", fallback: task.dueDateValue)
                        Button("Clear") {
                            taskDetailDraft?.dueText = ""
                            taskDetailDraft?.dueDate = nil
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    }
                }

                if !dueTextBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   resolvedDueDate == nil {
                    Text("Try phrases like `tomorrow at 3`, `next week tuesday`, or `mar 5 2pm`.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("Notes", systemImage: "note.text")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)

                TextEditor(text: noteBinding)
                    .font(.system(size: 15, weight: .regular))
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .focused($focusedTaskDetailField, equals: .note)
                    .frame(minHeight: 120)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.thinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(panelStrokeColor, lineWidth: 1)
                            )
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(glassPanel(cornerRadius: 16))
        .onAppear {
            if taskDetailDraft?.id != task.id {
                resetTaskDetailDraft(from: task)
            }
        }
    }

    // MARK: - Bulk Actions

    private var bulkActionsBar: some View {
        HStack(spacing: 12) {
            Text("\(viewModel.selectedTaskIDs.count) selected")
                .font(.system(size: 13, weight: .bold))

            Spacer()

            Button("Mark Done") { viewModel.bulkMarkDone() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.green.opacity(0.15)))
                .overlay(Capsule().stroke(Color.green.opacity(0.3), lineWidth: 1))

            Button("Snooze") { viewModel.bulkSnooze() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.orange.opacity(0.15)))
                .overlay(Capsule().stroke(Color.orange.opacity(0.3), lineWidth: 1))

            Button("Delete") { showDeleteConfirmation = true }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.red)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.red.opacity(0.15)))
                .overlay(Capsule().stroke(Color.red.opacity(0.3), lineWidth: 1))

            Button("Deselect") { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { viewModel.clearSelection() } }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.gray.opacity(0.12)))
                .overlay(Capsule().stroke(Color.gray.opacity(0.25), lineWidth: 1))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(glassPanel(cornerRadius: 12))
    }

    // MARK: - Style Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .kerning(0.7)
            .foregroundStyle(.secondary)
    }

    private var panelStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }

    private var composerInputIsFocused: Bool {
        focusedComposerField == .main
    }

    private var composerInputStrokeColor: Color {
        if composerInputIsFocused {
            return Color.accentColor.opacity(0.58)
        }
        if isComposerInputHovering {
            return Color.accentColor.opacity(0.34)
        }
        return panelStrokeColor
    }

    private var composerInputStrokeWidth: CGFloat {
        if composerInputIsFocused { return 1.6 }
        if isComposerInputHovering { return 1.2 }
        return 1
    }

    private var panelGradientColors: [Color] {
        colorScheme == .dark
            ? [Color.white.opacity(0.08), Color.white.opacity(0.03)]
            : [Color.white.opacity(0.72), Color.white.opacity(0.52)]
    }

    private func glassPanel(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(LinearGradient(colors: panelGradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(panelStrokeColor, lineWidth: 1)
            )
    }

    private func metadataCard(text: String, field: MetadataField, color: Color) -> some View {
        let selected = selectedMetadataField == field
        return Button {
            if field == selectedMetadataField {
                cycleValueIfApplicable(for: field)
            } else {
                selectedMetadataField = field
                syncMetadataEditorInputFromSelection()
                focusSelectedMetadataField()
            }
        } label: {
            Text(text)
                .lineLimit(1)
                .truncationMode(.tail)
                .font(.system(size: 12, weight: .semibold))
                .padding(.vertical, 4)
                .padding(.horizontal, 10)
                .background(
                    Capsule().fill(color.opacity(selected ? 0.26 : 0.18))
                )
                .overlay(
                    Capsule().stroke(color.opacity(selected ? 0.7 : 0.35), lineWidth: selected ? 1.5 : 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var composerInputPlaceholder: String {
        if selectedMetadataField == .main, let command = composer.command {
            return command.prompt
        }
        if selectedMetadataField == .main {
            switch viewModel.selectedItem {
            case .meeting: return "Add to this meeting..."
            default: return "What do you need to do?"
            }
        }
        return selectedMetadataField.placeholder
    }

    private var composerCommandSuggestions: [InputCommand] {
        guard selectedMetadataField == .main else { return [] }
        return InputCommandParser.suggestedCommands(for: metadataEditorInput)
    }

    private func composerCommandPill(_ command: InputCommand) -> some View {
        HStack(spacing: 6) {
            Image(systemName: commandIcon(for: command))
                .font(.system(size: 11, weight: .bold))
            Text(command.label)
                .font(.system(size: 14, weight: .bold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(commandColor(for: command).opacity(0.24)))
        .overlay(Capsule().stroke(commandColor(for: command).opacity(0.58), lineWidth: 1.5))
        .foregroundStyle(commandColor(for: command).opacity(0.95))
    }

    private var composerCommandSuggestionsPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(composerCommandSuggestions, id: \.id) { command in
                HStack(spacing: 8) {
                    Text(command.trigger)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 84, alignment: .leading)
                    Text(command.label)
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(command.prompt)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.thinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(panelStrokeColor, lineWidth: 1))
        )
    }

    // MARK: - Resolver Logic

    private static let queueSignalPhrases = [
        "follow up", "follow-up", "check in", "check-in", "reach out", "remind", "email", "call", "text", "ping", "contact", "message"
    ]

    private var parsedMain: ParsedTask {
        TaskParser.parse(composer.rawInput, fallbackToRawTitle: false)
    }

    private var resolvedQueue: TaskQueue {
        if let command = composer.command, case let .queue(queue) = command.kind {
            return queue
        }
        if hasQueueSignal(composer.rawInput) {
            return parsedMain.queue
        }
        return composer.queue
    }

    private var resolvedPerson: String? {
        if let parsedPerson = parsedMain.person {
            return TaskTextFormatter.formattedPerson(parsedPerson)
        }
        return TaskTextFormatter.formattedPerson(composer.person)
    }

    private var resolvedDueDate: Date? {
        if let fromDueField = parseDatePhrase(composer.dueText, baseDate: composer.dueDate) {
            return fromDueField
        }
        if let dueDate = composer.dueDate {
            return dueDate
        }
        if let parsedDue = parsedMain.dueDate {
            return parsedDue
        }
        return nil
    }

    private var resolvedNote: String? {
        if resolvedQueue == .thought {
            return TaskTextFormatter.formattedNote(composer.note)
        }
        if let parsedNote = parsedMain.note {
            return TaskTextFormatter.formattedNote(parsedNote)
        }
        return TaskTextFormatter.formattedNote(composer.note)
    }

    private var resolvedTitle: String {
        if resolvedQueue == .thought {
            let noteTitle = composer.rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
            if !noteTitle.isEmpty {
                return TaskTextFormatter.formattedTitle(noteTitle)
            }
        }

        let candidate = parsedMain.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !candidate.isEmpty {
            return TaskTextFormatter.formattedTitle(candidate)
        }
        if composer.isEditing, let baseTitle = editingBaseTask?.title {
            return TaskTextFormatter.formattedTitle(baseTitle)
        }
        let fallback = composer.rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        return TaskTextFormatter.formattedTitle(fallback)
    }

    private func hasQueueSignal(_ input: String) -> Bool {
        if let command = composer.command, case .queue = command.kind {
            return true
        }
        let lower = input.lowercased()
        if lower.range(of: #"(?:^|\s)/(?:w|r|t)(?=\s|$)"#, options: .regularExpression) != nil {
            return true
        }
        if lower.hasPrefix("//") {
            return true
        }
        return Self.queueSignalPhrases.contains { lower.contains($0) }
    }

    // MARK: - Date Parsing

    private func parseDatePhrase(_ phrase: String, baseDate: Date? = nil) -> Date? {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let exact = parseExplicitDateValue(trimmed) {
            return exact
        }

        let parsedDate = TaskParser.parse(trimmed, fallbackToRawTitle: false).dueDate
        let parsedTime = parseTimeComponents(from: trimmed)

        if let parsedDate {
            return applyingTime(parsedTime, to: parsedDate)
        }

        guard let parsedTime else { return nil }
        let anchor = baseDate ?? Date()
        return applyingTime(parsedTime, to: anchor)
    }

    private func parseExplicitDateValue(_ input: String) -> Date? {
        if let date = dueFieldFormatter.date(from: input) {
            return date
        }

        let formatterStyles: [(DateFormatter.Style, DateFormatter.Style)] = [
            (.short, .short), (.medium, .short), (.long, .short),
            (.short, .none), (.medium, .none), (.long, .none)
        ]

        for style in formatterStyles {
            let formatter = DateFormatter()
            formatter.locale = .current
            formatter.dateStyle = style.0
            formatter.timeStyle = style.1
            if let date = formatter.date(from: input) {
                return date
            }
        }

        return ISO8601DateFormatter().date(from: input)
    }

    private func parseTimeComponents(from input: String) -> DateComponents? {
        if let parsed = TaskParser.parseTimeComponents(from: input) {
            return parsed
        }

        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isStandaloneTimePhrase(trimmed) else { return nil }
        return TaskParser.parseTimeComponents(from: trimmed, allowBareNumericTime: true)
    }

    private func isStandaloneTimePhrase(_ input: String) -> Bool {
        let normalized = input.lowercased().replacingOccurrences(of: ".", with: "")
        let patterns = [
            #"^(?:noon|midday|midnight)$"#,
            #"^\d{1,2}(?::[0-5]\d)?\s*[ap]m$"#,
            #"^\d{1,2}:\d{2}$"#,
            #"^\d{1,2}$"#
        ]

        return patterns.contains { pattern in
            normalized.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private func applyingTime(_ time: DateComponents?, to date: Date) -> Date {
        guard let time else { return date }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0
        return Calendar.current.date(from: components) ?? date
    }

    // MARK: - Submit / Editing

    private var composerMeetingId: String? {
        if case .meeting(let id) = viewModel.selectedItem { return id }
        return nil
    }

    private var editingBaseTask: Task? {
        guard let editingTaskID = composer.editingTaskID else { return nil }
        return viewModel.tasks.first(where: { $0.id == editingTaskID })
    }

    private func submitComposer() {
        switch composer.command?.kind {
        case .meetingStart:
            let draft = MeetingDraftParser.parse(composer.rawInput)
            guard !draft.title.isEmpty else { return }
            try? meetingSession.startMeeting(title: draft.title, attendees: draft.person)
            if let active = meetingSession.activeMeeting {
                viewModel.selectedItem = .meeting(active.id)
            }
            startNewComposer()
            return
        case .meetingEnd:
            let summary = TaskTextFormatter.formattedNote(composer.rawInput) ?? meetingSession.meetingSummary
            try? meetingSession.endCurrentMeeting(summary: summary)
            startNewComposer()
            return
        case .meetingSummary:
            let summary = TaskTextFormatter.formattedNote(composer.rawInput)
            try? meetingSession.updateActiveMeetingSummary(summary)
            startNewComposer()
            return
        default:
            break
        }

        let title = resolvedTitle
        guard !title.isEmpty else { return }

        let person = resolvedPerson
        let dueDate = resolvedDueDate
        let note = resolvedNote

        if let editingTaskID = composer.editingTaskID {
            viewModel.updateTask(
                id: editingTaskID,
                rawInput: composer.rawInput,
                title: title,
                queue: resolvedQueue,
                status: composer.status,
                person: person,
                dueDate: dueDate,
                note: note
            )
        } else {
            if resolvedQueue == .thought, let meetingId = composerMeetingId {
                viewModel.captureMeetingNote(
                    rawInput: composer.rawInput,
                    content: title,
                    meetingId: meetingId
                )
            } else {
                viewModel.createTask(
                    rawInput: composer.rawInput,
                    title: title,
                    queue: resolvedQueue,
                    person: person,
                    dueDate: dueDate,
                    note: note,
                    meetingId: composerMeetingId
                )
            }
        }

        startNewComposer()
    }

    private func beginEditing(_ task: Task) {
        viewModel.selectedTaskIDs = [task.id]
        resetTaskDetailDraft(from: task)
        focusedComposerField = nil
    }

    private func syncTaskDetailDraftFromSelection(force: Bool = false) {
        guard let task = currentSelectedTask else {
            taskDetailDraft = nil
            pendingTaskDetailSyncID = nil
            return
        }
        if force || taskDetailDraft?.id != task.id || pendingTaskDetailSyncID == task.id {
            resetTaskDetailDraft(from: task)
        }
    }

    private func resetTaskDetailDraft(from task: Task) {
        taskDetailDraft = TaskDetailDraft(task: task, dueFormatter: dueFieldFormatter)
        pendingTaskDetailSyncID = nil
    }

    private func taskDetailBinding<Value>(_ keyPath: WritableKeyPath<TaskDetailDraft, Value>, default fallback: Value) -> Binding<Value> {
        Binding(
            get: { taskDetailDraft?[keyPath: keyPath] ?? fallback },
            set: { newValue in
                guard taskDetailDraft != nil else { return }
                taskDetailDraft![keyPath: keyPath] = newValue
            }
        )
    }

    private func updateTaskDetailDueText(_ text: String, fallback: Date?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            taskDetailDraft?.dueDate = nil
            return
        }

        if let parsed = parseDatePhrase(trimmed, baseDate: taskDetailDraft?.dueDate ?? fallback) {
            taskDetailDraft?.dueDate = parsed
        }
    }

    private func resolvedTaskDetailDueDate(fallback: Date?) -> Date? {
        guard let draft = taskDetailDraft else { return fallback }
        let dueText = draft.dueText.trimmingCharacters(in: .whitespacesAndNewlines)
        if dueText.isEmpty {
            return nil
        }
        return parseDatePhrase(dueText, baseDate: draft.dueDate ?? fallback)
    }

    private func taskDetailQuickDateButton(_ title: String, phrase: String, fallback: Date?) -> some View {
        Button(title) {
            taskDetailDraft?.dueText = phrase
            updateTaskDetailDueText(phrase, fallback: fallback)
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.secondary.opacity(0.1)))
        .overlay(Capsule().stroke(Color.secondary.opacity(0.2), lineWidth: 1))
    }

    @discardableResult
    private func saveTaskDetailEdits(closeAfterSaving: Bool = false) -> Bool {
        guard let draft = taskDetailDraft else { return false }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }

        let dueText = draft.dueText.trimmingCharacters(in: .whitespacesAndNewlines)
        let dueDate: Date?
        if dueText.isEmpty {
            dueDate = nil
        } else {
            guard let parsed = parseDatePhrase(dueText, baseDate: draft.dueDate) else { return false }
            dueDate = parsed
        }

        pendingTaskDetailSyncID = draft.id
        viewModel.updateTask(
            id: draft.id,
            rawInput: title,
            title: title,
            queue: draft.queue,
            status: draft.status,
            person: TaskTextFormatter.formattedPerson(draft.person),
            dueDate: dueDate,
            note: TaskTextFormatter.formattedNote(draft.note)
        )
        if closeAfterSaving {
            focusedTaskDetailField = nil
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                viewModel.clearSelection()
            }
        }
        return true
    }

    private func syncMeetingSummaryDraft() {
        if case .meeting = viewModel.selectedItem {
            meetingSummaryDraft = viewModel.selectedMeeting?.summary ?? ""
        }
    }

    private func supportsNoteSelection(for item: TaskListViewModel.SidebarItem) -> Bool {
        switch item {
        case .inbox, .meeting:
            return true
        default:
            return false
        }
    }

    private func saveMeetingSummary(_ meeting: Meeting) {
        let trimmed = meetingSummaryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        viewModel.updateMeetingSummary(meeting, summary: trimmed.isEmpty ? nil : TaskTextFormatter.formattedNote(trimmed))
        meetingSummaryDraft = trimmed.isEmpty ? "" : TaskTextFormatter.formattedNote(trimmed) ?? ""
    }

    @ViewBuilder
    private func meetingPanel(_ meeting: Meeting, items: [Task]) -> some View {
        let notes = items.filter { $0.queue == .thought }
        let tasks = items.filter { $0.queue == .work }
        let followUps = items.filter { $0.queue == .reachOut }

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                meetingHeader(meeting)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Summary", systemImage: "text.bubble")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Save Summary") {
                            saveMeetingSummary(meeting)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    }

                    TextEditor(text: $meetingSummaryDraft)
                        .font(.system(size: 14, weight: .regular))
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .frame(minHeight: 90)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.thinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(panelStrokeColor, lineWidth: 1)
                                )
                        )
                }

                Divider()

                if items.isEmpty {
                    Text("Nothing captured yet during this meeting.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                } else {
                    if !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionHeader("Notes")
                            ForEach(notes) { thought in
                                thoughtRow(thought)
                            }
                        }
                    }

                    if !tasks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionHeader("Tasks")
                            ForEach(tasks) { task in
                                meetingTaskRow(task)
                            }
                        }
                    }

                    if !followUps.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionHeader("Follow Up")
                            ForEach(followUps) { task in
                                meetingTaskRow(task)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(glassPanel(cornerRadius: 16))
    }

    private func meetingHeader(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(meeting.title)
                .font(.system(size: 22, weight: .bold))

            HStack(spacing: 12) {
                if let start = meeting.startedAtValue {
                    Label(meetingDateFormatter.string(from: start), systemImage: "calendar")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                if !meeting.formattedDuration.isEmpty {
                    Label(meeting.formattedDuration, systemImage: "clock")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                if meeting.isActive {
                    Label("In Progress", systemImage: "record.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.red)
                }
            }

            if !meeting.attendeeList.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "person")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("With \(meeting.attendeeList.joined(separator: ", "))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private func meetingTaskRow(_ task: Task) -> some View {
        TaskRowView(
            task: task,
            isSelected: viewModel.selectedTaskIDs.contains(task.id),
            showQueueBadge: false,
            onToggle: { viewModel.toggleDone(task) }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            closeThoughtEditor()
            viewModel.selectedTaskIDs = [task.id]
        }
        .contextMenu {
            Button("Edit") {
                closeThoughtEditor()
                beginEditing(task)
            }
            Button("Add to Today List") { viewModel.addTaskToDailyFocus(task) }
            Button("Snooze") { viewModel.snooze(task) }
            Button("Delete", role: .destructive) { viewModel.delete(task) }
        }
    }

    private var meetingDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    private func startNewComposer() {
        let defaultQueue = defaultComposerQueue(for: viewModel.selectedItem) ?? settings.defaultQueue
        composer = TaskComposerState.capture(defaultQueue: defaultQueue)
        selectedMetadataField = .main
        syncMetadataEditorInputFromSelection()
        focusPrompt()
    }

    private func defaultComposerQueue(for item: TaskListViewModel.SidebarItem) -> TaskQueue? {
        switch item {
        case .work:
            return .work
        case .followUp:
            return .reachOut
        case .inbox, .meeting:
            return .thought
        default:
            return nil
        }
    }

    private func focusPrompt() {
        selectedMetadataField = .main
        focusedComposerField = .main
    }

    private func cycleMetadataField(reverse: Bool) {
        let fields = metadataFieldsForTabCycle()
        guard !fields.isEmpty else { return }
        guard let index = fields.firstIndex(of: selectedMetadataField) else {
            selectedMetadataField = fields[0]
            syncMetadataEditorInputFromSelection()
            focusSelectedMetadataField()
            return
        }
        let delta = reverse ? -1 : 1
        let next = (index + delta + fields.count) % fields.count
        selectedMetadataField = fields[next]
        syncMetadataEditorInputFromSelection()
        focusSelectedMetadataField()
    }

    private func metadataFieldsForTabCycle() -> [MetadataField] {
        if composer.command?.kind == .meetingStart ||
            composer.command?.kind == .meetingEnd ||
            composer.command?.kind == .meetingSummary {
            return [.main]
        }
        var fields: [MetadataField] = [.main, .queue, .due, .note]
        if composer.isEditing {
            fields.append(.status)
        }
        return fields
    }

    private func focusSelectedMetadataField() {
        focusedComposerField = .main
    }

    private func syncMetadataEditorInputFromSelection() {
        switch selectedMetadataField {
        case .main: metadataEditorInput = composer.rawInput
        case .queue: metadataEditorInput = queueInputLabel(composer.queue)
        case .due: metadataEditorInput = composer.dueText
        case .note: metadataEditorInput = composer.note
        case .status: metadataEditorInput = composer.status.rawValue
        }
    }

    private func applyMetadataEditorInput() {
        switch selectedMetadataField {
        case .main:
            if let consumed = InputCommandParser.consumeLeadingCommand(from: metadataEditorInput) {
                composer.command = consumed.command
                if case let .queue(queue) = consumed.command.kind {
                    composer.queue = queue
                }
                let expandedRemainder = InputCommandParser.expandedRemainder(for: consumed.command, remainder: consumed.remainder)
                if metadataEditorInput != expandedRemainder {
                    metadataEditorInput = expandedRemainder
                }
                composer.rawInput = expandedRemainder
                return
            }
            composer.rawInput = metadataEditorInput
        case .queue:
            if let parsedQueue = parseQueueValue(metadataEditorInput) {
                composer.command = nil
                composer.queue = parsedQueue
            }
        case .due:
            composer.dueText = metadataEditorInput
            let trimmed = metadataEditorInput.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                composer.dueDate = nil
            } else if let parsed = parseDatePhrase(trimmed, baseDate: composer.dueDate) {
                composer.dueDate = parsed
            }
        case .note:
            composer.note = metadataEditorInput
        case .status:
            if let parsedStatus = parseStatusValue(metadataEditorInput) {
                composer.status = parsedStatus
            }
        }
    }

    private func cycleValueIfApplicable(for field: MetadataField) {
        switch field {
        case .queue:
            composer.command = nil
            switch composer.queue {
            case .work: composer.queue = .reachOut
            case .reachOut: composer.queue = .thought
            case .thought: composer.queue = .work
            }
            metadataEditorInput = queueInputLabel(composer.queue)
        case .status where composer.isEditing:
            let next: TaskStatus
            switch composer.status {
            case .active: next = .done
            case .done: next = .archived
            case .archived: next = .active
            }
            composer.status = next
            metadataEditorInput = next.rawValue
        default:
            selectedMetadataField = field
            syncMetadataEditorInputFromSelection()
            focusSelectedMetadataField()
        }
    }

    // MARK: - Keyboard Handlers

    private func handleEscape() {
        if selectedNoteID != nil {
            closeThoughtEditor()
            return
        }
        if composer.isEditing {
            startNewComposer()
            focusedComposerField = nil
        } else if focusedComposerField != nil {
            focusedComposerField = nil
        } else if viewModel.hasSelection {
            focusedTaskDetailField = nil
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                viewModel.clearSelection()
            }
        } else {
            focusPrompt()
        }
    }

    private var canUseListKeyboardShortcuts: Bool {
        focusedComposerField == nil && focusedTaskDetailField == nil
    }

    private func handleListArrowUp() -> Bool {
        guard canUseListKeyboardShortcuts else { return false }
        if case .meeting = viewModel.selectedItem { return false }
        viewModel.moveSelectionUp()
        return true
    }

    private func handleListArrowDown() -> Bool {
        guard canUseListKeyboardShortcuts else { return false }
        if case .meeting = viewModel.selectedItem { return false }
        viewModel.moveSelectionDown()
        return true
    }

    private func handleListEnter() -> Bool {
        guard canUseListKeyboardShortcuts else { return false }
        guard let task = currentSelectedTask else { return false }
        beginEditing(task)
        return true
    }

    private func handleListSpace() -> Bool {
        guard canUseListKeyboardShortcuts else { return false }
        guard viewModel.hasSelection else { return false }
        for task in viewModel.selectedTasks {
            viewModel.toggleDone(task)
        }
        return true
    }

    private func handleListDelete() -> Bool {
        if focusedComposerField == .main,
           selectedMetadataField == .main,
           metadataEditorInput.isEmpty,
           composer.command != nil {
            composer.command = nil
            return true
        }
        guard canUseListKeyboardShortcuts else { return false }
        guard viewModel.hasSelection else { return false }
        if viewModel.isMultiSelect {
            showDeleteConfirmation = true
        } else {
            viewModel.bulkDelete()
        }
        return true
    }

    private func handleSelectAll() -> Bool {
        guard canUseListKeyboardShortcuts else { return false }
        guard viewModel.selectedMeeting == nil else { return false }
        viewModel.selectAll()
        return true
    }

    // MARK: - Utility

    private func parseQueueValue(_ input: String) -> TaskQueue? {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("thought") || normalized.contains("note") || normalized.contains("inbox") || normalized == "n" || normalized == "//" {
            return .thought
        }
        if normalized.contains("follow") || normalized.contains("reach") || normalized == "r" {
            return .reachOut
        }
        if normalized.contains("work") || normalized == "w" {
            return .work
        }
        return nil
    }

    private func queueInputLabel(_ queue: TaskQueue) -> String {
        switch queue {
        case .work: return "work"
        case .reachOut: return "follow up"
        case .thought: return "note"
        }
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
        case let .queue(queue): return queueColor(queue)
        case .meetingStart, .meetingEnd, .meetingSummary: return .purple
        case .today: return .orange
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
        case .meetingStart: return "video.fill"
        case .meetingEnd: return "record.circle"
        case .meetingSummary: return "text.bubble"
        case .today: return "sun.max.fill"
        }
    }

    private func parseStatusValue(_ input: String) -> TaskStatus? {
        switch input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "active": return .active
        case "done", "complete", "completed": return .done
        case "archived", "archive": return .archived
        default: return nil
        }
    }

    private var dueFieldFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
}

// MARK: - Supporting Types

private struct TaskDetailDraft {
    var id: String
    var title: String
    var queue: TaskQueue
    var status: TaskStatus
    var person: String
    var dueText: String
    var dueDate: Date?
    var note: String

    init(task: Task, dueFormatter: DateFormatter) {
        id = task.id
        title = task.title
        queue = task.queue
        status = task.status
        person = task.person ?? ""
        dueText = task.dueDateValue.map(dueFormatter.string(from:)) ?? ""
        dueDate = task.dueDateValue
        note = task.note ?? ""
    }
}

private struct TaskComposerState {
    var editingTaskID: String?
    var command: InputCommand?
    var rawInput: String
    var queue: TaskQueue
    var status: TaskStatus
    var person: String
    var dueText: String
    var dueDate: Date?
    var note: String

    var isEditing: Bool {
        editingTaskID != nil
    }

    static func capture(defaultQueue: TaskQueue) -> TaskComposerState {
        TaskComposerState(
            editingTaskID: nil,
            command: nil,
            rawInput: "",
            queue: defaultQueue,
            status: .active,
            person: "",
            dueText: "",
            dueDate: nil,
            note: ""
        )
    }

    static func edit(task: Task) -> TaskComposerState {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        return TaskComposerState(
            editingTaskID: task.id,
            command: nil,
            rawInput: task.title,
            queue: task.queue,
            status: task.status,
            person: task.person ?? "",
            dueText: task.dueDateValue.map(formatter.string(from:)) ?? "",
            dueDate: task.dueDateValue,
            note: task.note ?? ""
        )
    }
}

// MARK: - Key Monitor

private struct MainPromptKeyMonitor: NSViewRepresentable {
    var onEscape: () -> Void
    var onFocusPrompt: () -> Void
    var onTab: (_ reverse: Bool) -> Void
    var onArrowUp: () -> Bool
    var onArrowDown: () -> Bool
    var onEnter: () -> Bool
    var onSpace: () -> Bool
    var onDelete: () -> Bool
    var onSelectAll: () -> Bool

    func makeNSView(context: Context) -> NSView {
        let view = MainPromptKeyMonitorView()
        view.onEscape = onEscape
        view.onFocusPrompt = onFocusPrompt
        view.onTab = onTab
        view.onArrowUp = onArrowUp
        view.onArrowDown = onArrowDown
        view.onEnter = onEnter
        view.onSpace = onSpace
        view.onDelete = onDelete
        view.onSelectAll = onSelectAll
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? MainPromptKeyMonitorView else { return }
        view.onEscape = onEscape
        view.onFocusPrompt = onFocusPrompt
        view.onTab = onTab
        view.onArrowUp = onArrowUp
        view.onArrowDown = onArrowDown
        view.onEnter = onEnter
        view.onSpace = onSpace
        view.onDelete = onDelete
        view.onSelectAll = onSelectAll
    }
}

private final class MainPromptKeyMonitorView: NSView {
    var onEscape: (() -> Void)?
    var onFocusPrompt: (() -> Void)?
    var onTab: ((Bool) -> Void)?
    var onArrowUp: (() -> Bool)?
    var onArrowDown: (() -> Bool)?
    var onEnter: (() -> Bool)?
    var onSpace: (() -> Bool)?
    var onDelete: (() -> Bool)?
    var onSelectAll: (() -> Bool)?
    private var monitor: Any?

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        guard window != nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if event.keyCode == 53 { // Escape
                self.onEscape?()
                return nil
            }

            let isCommandL = event.keyCode == 37 && modifiers.contains(.command)
            if isCommandL {
                self.onFocusPrompt?()
                return nil
            }

            if event.keyCode == 48 { // Tab
                let reverse = modifiers.contains(.shift)
                self.onTab?(reverse)
                return nil
            }

            // Cmd+A: select all
            if event.keyCode == 0 && modifiers == .command {
                if self.onSelectAll?() == true { return nil }
                return event
            }

            // Arrow Up
            if event.keyCode == 126 && modifiers.isEmpty {
                if self.onArrowUp?() == true { return nil }
                return event
            }

            // Arrow Down
            if event.keyCode == 125 && modifiers.isEmpty {
                if self.onArrowDown?() == true { return nil }
                return event
            }

            // Enter
            if event.keyCode == 36 && modifiers.isEmpty {
                if self.onEnter?() == true { return nil }
                return event
            }

            // Space
            if event.keyCode == 49 && modifiers.isEmpty {
                if self.onSpace?() == true { return nil }
                return event
            }

            // Cmd+Delete
            if event.keyCode == 51 && modifiers == .command {
                if self.onDelete?() == true { return nil }
                return event
            }

            return event
        }
    }
}

// MARK: - Thought Row

private struct ThoughtRowView: View {
    @Environment(\.colorScheme) private var colorScheme
    let thought: Task
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.indigo.opacity(0.6))
                    .frame(width: 18)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(thought.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    if let created = thought.createdAtValue {
                        Text(RelativeDateTimeFormatter().localizedString(for: created, relativeTo: .now))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "pencil.circle.fill" : "pencil")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                isSelected
                                    ? LinearGradient(
                                        colors: selectedGradientColors,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                    : LinearGradient(
                                        colors: rowGradientColors,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.accentColor.opacity(0.3) : rowStrokeColor, lineWidth: 1)
                    )
                    .animation(.easeOut(duration: 0.15), value: isHovering)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)
            .onHover { hovering in
                isHovering = hovering
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit Note") { onSelect() }
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .draggable("jot-task:\(thought.id)")
    }

    private var selectedGradientColors: [Color] {
        if colorScheme == .dark {
            return [Color.accentColor.opacity(0.10), Color.accentColor.opacity(0.05)]
        }
        return [Color.accentColor.opacity(0.08), Color.accentColor.opacity(0.04)]
    }

    private var rowStrokeColor: Color {
        if colorScheme == .dark {
            return Color.white.opacity(isHovering ? 0.16 : 0.08)
        } else {
            return Color.black.opacity(isHovering ? 0.14 : 0.08)
        }
    }

    private var rowGradientColors: [Color] {
        if colorScheme == .dark {
            return [Color.white.opacity(isHovering ? 0.13 : 0.11), Color.white.opacity(isHovering ? 0.07 : 0.05)]
        }
        return [Color.white.opacity(isHovering ? 0.98 : 0.92), Color.white.opacity(isHovering ? 0.82 : 0.70)]
    }
}
