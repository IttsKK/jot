import SwiftUI

struct MainTaskListView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var meetingSession: MeetingSession
    @StateObject private var viewModel: TaskListViewModel
    @State private var archiveExpanded = false
    @State private var composer: TaskComposerState
    @State private var showDeleteConfirmation = false
    @State private var selectedMetadataField: MetadataField = .main
    @State private var selectedMeeting: Meeting? = nil
    @State private var metadataEditorInput: String = ""
    @FocusState private var focusedComposerField: ComposerField?

    private enum ComposerField: Hashable {
        case main
        case auxiliary
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
            case .queue: return "work or follow up"
            case .due: return "tomorrow, next week thursday, mar 5..."
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

    var body: some View {
        ZStack {
            backgroundLayer

            VStack(spacing: 14) {
                topPanel

                if viewModel.selectedTab == .meetings {
                    meetingsPanel
                } else if viewModel.selectedTab == .inbox {
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

                    if let task = singleSelectedTask {
                        taskDetailsPanel(task: task)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    composerPanel
                }
            }
            .animation(.easeOut(duration: 0.18), value: singleSelectedTask?.id)
            .padding(20)
        }
        .background(
            MainPromptKeyMonitor(
                onEscape: { handleEscape() },
                onFocusPrompt: { focusPrompt() },
                onTab: { reverse in cycleMetadataField(reverse: reverse) },
                onArrowUp: { handleListArrowUp() },
                onArrowDown: { handleListArrowDown() },
                onArrowLeft: { handleArrowLeft() },
                onArrowRight: { handleArrowRight() },
                onEnter: { handleListEnter() },
                onSpace: { handleListSpace() },
                onDelete: { handleListDelete() },
                onSelectAll: { handleSelectAll() }
            )
        )
        .task {
            try? viewModel.refresh()
        }
        .onChange(of: viewModel.tasks) { _, _ in
            viewModel.validateSelection()
        }
        .onChange(of: viewModel.selectedTab) { _, _ in
            viewModel.validateSelection()
        }
        .alert("Delete \(viewModel.selectedTaskIDs.count) tasks?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) { viewModel.bulkDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
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

    private var topPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Jot")
                        .font(.system(size: 30, weight: .bold, design: .rounded))

                    Text(meetingSession.isInMeeting ? "In meeting: \(meetingSession.activeMeeting?.title ?? "")" : "Keep work and follow ups moving")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(meetingSession.isInMeeting ? Color.purple.opacity(0.85) : .secondary)
                }

                Spacer()
            }

            HStack(spacing: 8) {
                tabButton(.all, shortcut: "1")
                tabButton(.work, shortcut: "2")
                tabButton(.reachOut, shortcut: "3")
                tabButton(.meetings, shortcut: "4")
                tabButton(.inbox, shortcut: "5")
                Spacer()
            }
        }
        .padding(16)
        .background(glassPanel(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.06), radius: 12, y: 5)
    }

    private var meetingsPanel: some View {
        HStack(spacing: 16) {
            // Meeting list sidebar
            VStack(alignment: .leading, spacing: 0) {
                Text("Meetings")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 8)

                if viewModel.meetings.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text("No meetings yet")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("Start a meeting from the menu bar")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(viewModel.meetings) { meeting in
                                meetingRow(meeting)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                    }
                }
            }
            .frame(width: 240)
            .frame(maxHeight: .infinity)
            .background(glassPanel(cornerRadius: 16))
            .shadow(color: Color.black.opacity(0.05), radius: 12, y: 5)

            // Meeting detail
            Group {
                if let meeting = selectedMeeting ?? viewModel.meetings.first(where: { $0.isActive }) ?? viewModel.meetings.first {
                    MeetingDetailView(
                        meeting: meeting,
                        items: viewModel.tasksForMeeting(meeting),
                        onToggleDone: { viewModel.toggleDone($0) },
                        onDelete: { viewModel.delete($0) }
                    )
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "note.text")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("Select a meeting")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(glassPanel(cornerRadius: 16))
            .shadow(color: Color.black.opacity(0.05), radius: 12, y: 5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func meetingRow(_ meeting: Meeting) -> some View {
        let isSelected = selectedMeeting?.id == meeting.id
        return Button {
            selectedMeeting = meeting
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if meeting.isActive {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 7, height: 7)
                        }
                        Text(meeting.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.blue.opacity(0.95) : .primary)
                            .lineLimit(1)
                    }

                    if let start = meeting.startedAtValue {
                        Text(shortDateFormatter.string(from: start))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    if !meeting.attendeeList.isEmpty {
                        Text(meeting.attendeeList.joined(separator: ", "))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                let count = viewModel.tasksForMeeting(meeting).count
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.blue.opacity(0.15)))
                        .foregroundStyle(Color.blue.opacity(0.8))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.blue.opacity(0.12) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Color.blue.opacity(0.25) : Color.clear, lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                if selectedMeeting?.id == meeting.id { selectedMeeting = nil }
                viewModel.deleteMeeting(meeting)
            } label: {
                Label("Delete Meeting", systemImage: "trash")
            }
        }
    }

    private var shortDateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }

    private var inboxPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Inbox")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                Text("—")
                    .foregroundStyle(.tertiary)
                Text("Brain dumps and random thoughts")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("Type // or /t to capture a thought")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            if viewModel.thoughts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "brain")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("Nothing in your inbox")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Use // or /t in quick capture to dump a thought.\nNo structure needed.")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(viewModel.thoughts) { thought in
                            thoughtRow(thought)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(glassPanel(cornerRadius: 18))
        .shadow(color: Color.black.opacity(0.05), radius: 14, y: 5)
    }

    private func thoughtRow(_ thought: Task) -> some View {
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
                    .fixedSize(horizontal: false, vertical: true)

                if let created = thought.createdAtValue {
                    Text(RelativeDateTimeFormatter().localizedString(for: created, relativeTo: .now))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(panelStrokeColor, lineWidth: 1)
                )
        )
        .contextMenu {
            Button(role: .destructive) { viewModel.delete(thought) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var taskListPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(viewModel.activeTasks.count) active")
                Text("•")
                Text("\(viewModel.completedTasks.count) completed")
                if !viewModel.archivedTasks.isEmpty {
                    Text("•")
                    Text("\(viewModel.archivedTasks.count) archived")
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
                            showQueueBadge: viewModel.selectedTab == .all,
                            onToggle: { viewModel.toggleDone(task) }
                        )
                        .tag(task.id)
                        .contextMenu {
                            Button("Edit") { beginEditing(task) }
                            Button("Snooze") { viewModel.snooze(task) }
                            Button("Delete", role: .destructive) { viewModel.delete(task) }
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 4, trailing: 8))
                    }
                    .onMove(perform: viewModel.moveActive)
                } header: {
                    sectionHeader("Active")
                }

                if !viewModel.completedTasks.isEmpty {
                    Section {
                        ForEach(viewModel.completedTasks) { task in
                            TaskRowView(
                                task: task,
                                isSelected: viewModel.selectedTaskIDs.contains(task.id),
                                showQueueBadge: viewModel.selectedTab == .all,
                                onToggle: { viewModel.toggleDone(task) }
                            )
                            .tag(task.id)
                            .contextMenu {
                                Button("Edit") { beginEditing(task) }
                                Button("Delete", role: .destructive) { viewModel.delete(task) }
                            }
                            .opacity(0.72)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 4, trailing: 8))
                        }
                    } header: {
                        sectionHeader("Completed")
                    }
                }

                if !viewModel.archivedTasks.isEmpty {
                    Section {
                        if archiveExpanded {
                            ForEach(viewModel.archivedTasks) { task in
                                TaskRowView(
                                    task: task,
                                    isSelected: viewModel.selectedTaskIDs.contains(task.id),
                                    showQueueBadge: viewModel.selectedTab == .all,
                                    onToggle: {}
                                )
                                .tag(task.id)
                                .contextMenu {
                                    Button("Edit") { beginEditing(task) }
                                    Button("Delete", role: .destructive) { viewModel.delete(task) }
                                }
                                .opacity(0.56)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 4, trailing: 8))
                            }
                        }
                    } header: {
                        HStack {
                            sectionHeader("Archive")
                            Spacer()
                            Button(archiveExpanded ? "Hide" : "Show") {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    archiveExpanded.toggle()
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
        .background(glassPanel(cornerRadius: 18))
        .shadow(color: Color.black.opacity(0.05), radius: 14, y: 5)
    }

    private var emptyStatePanel: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 38))
                .foregroundStyle(.blue.opacity(0.75))

            Text("No tasks yet")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Text("Use the input bar at the bottom to add your first task. Type what you need to do, then press Enter.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 430)

            Button {
                focusPrompt()
            } label: {
                Label("Focus Input", systemImage: "keyboard")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(.thinMaterial)
                            .overlay(
                                Capsule()
                                    .stroke(panelStrokeColor, lineWidth: 1)
                            )
                    )
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("l", modifiers: [.command])
            .help("Focus the in-app input")
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(glassPanel(cornerRadius: 18))
        .shadow(color: Color.black.opacity(0.05), radius: 14, y: 5)
    }

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

                Button(composer.isEditing ? "Cancel Edit" : "New") {
                    startNewComposer()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            }

            TextField(composer.isEditing ? "Update this task..." : "Capture a new task...", text: $composer.rawInput)
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.thinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(panelStrokeColor, lineWidth: 1)
                        )
                )
                .focused($focusedComposerField, equals: .main)
                .onSubmit(submitComposer)

            HStack(spacing: 8) {
                metadataCard(
                    text: "Queue: \(resolvedQueue.displayName)",
                    field: .queue,
                    color: resolvedQueue == .work ? .orange : .blue
                )

                metadataCard(
                    text: resolvedDueDate.map(relativeDate) ?? "Due Date",
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

                Spacer()
                Text("Tab: Next Field • Shift+Tab: Previous • Enter: Save • Esc: Focus/Unfocus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            if selectedMetadataField != .main {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Editing \(selectedMetadataField.title)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        TextField(selectedMetadataField.placeholder, text: $metadataEditorInput)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedComposerField, equals: .auxiliary)
                            .onChange(of: metadataEditorInput) { _, _ in
                                applyMetadataEditorInput()
                            }
                            .onSubmit(submitComposer)

                        if selectedMetadataField == .due {
                            DatePicker(
                                "",
                                selection: Binding(
                                    get: { composer.dueDate ?? Date() },
                                    set: { newValue in
                                        composer.dueDate = newValue
                                        composer.dueText = dueFieldFormatter.string(from: newValue)
                                        metadataEditorInput = composer.dueText
                                    }
                                ),
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .datePickerStyle(.compact)
                        }
                    }
                }
            }
        }
        .onChange(of: composer.rawInput) { _, _ in
            if selectedMetadataField == .main {
                metadataEditorInput = composer.rawInput
            }
        }
        .padding(14)
        .background(glassPanel(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.05), radius: 10, y: 4)
    }

    private var singleSelectedTask: Task? {
        guard viewModel.selectedTaskIDs.count == 1, let id = viewModel.selectedTaskIDs.first else { return nil }
        return viewModel.visibleTasks.first(where: { $0.id == id })
    }

    private func taskDetailsPanel(task: Task) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Task Details")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Button("Edit") {
                    beginEditing(task)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                Button("Close") {
                    withAnimation(.easeOut(duration: 0.16)) {
                        viewModel.clearSelection()
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            }

            Text(task.title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)

            if let note = task.note, !note.isEmpty {
                detailLine(label: "Note", value: note)
            }

            HStack(spacing: 8) {
                keyChip("Queue: \(task.queue.displayName)")
                keyChip("Status: \(task.status.rawValue.capitalized)")
                if let dueDate = task.dueDateValue {
                    keyChip("Due: \(longDate(dueDate))")
                }
            }

            if !task.rawInput.isEmpty {
                detailLine(label: "Captured", value: task.rawInput)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(glassPanel(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 4)
    }

    private func detailLine(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .kerning(0.5)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .kerning(0.7)
            .foregroundStyle(.secondary)
    }

    private func keyChip(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 12, weight: .bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(colors: chipGradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(panelStrokeColor, lineWidth: 1)
                    )
            )
    }

    private func tabButton(_ tab: TaskListViewModel.Tab, shortcut: Character) -> some View {
        let isSelected = viewModel.selectedTab == tab
        let strokeColor = isSelected ? Color.blue.opacity(0.32) : panelStrokeColor
        let textColor = isSelected ? Color.blue.opacity(0.95) : Color.primary.opacity(0.8)
        let backgroundColors = isSelected
            ? [Color.blue.opacity(0.30), Color.blue.opacity(0.18)]
            : chipGradientColors

        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                viewModel.selectedTab = tab
            }
        } label: {
            Text(tab.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(textColor)
                .frame(minWidth: 68)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(.thinMaterial)
                        .overlay(
                            Capsule()
                                .fill(LinearGradient(colors: backgroundColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                        .overlay(
                            Capsule().stroke(strokeColor, lineWidth: 1)
                        )
                )
                .contentShape(Capsule())
        }
        .keyboardShortcut(KeyEquivalent(shortcut), modifiers: [.command])
        .buttonStyle(.plain)
    }

    private var panelStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }

    private var panelGradientColors: [Color] {
        colorScheme == .dark
            ? [Color.white.opacity(0.08), Color.white.opacity(0.03)]
            : [Color.white.opacity(0.72), Color.white.opacity(0.52)]
    }

    private var chipGradientColors: [Color] {
        colorScheme == .dark
            ? [Color.white.opacity(0.10), Color.white.opacity(0.04)]
            : [Color.white.opacity(0.70), Color.white.opacity(0.52)]
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

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    private func longDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private static let queueSignalPhrases = [
        "follow up", "follow-up", "check in", "check-in", "reach out", "email", "call", "text", "ping", "contact", "message"
    ]

    private var parsedMain: ParsedTask {
        TaskParser.parse(composer.rawInput, fallbackToRawTitle: false)
    }

    private var resolvedQueue: TaskQueue {
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
        if let parsedDue = parsedMain.dueDate {
            return parsedDue
        }
        if let fromDueField = parseDatePhrase(composer.dueText) {
            return fromDueField
        }
        return composer.dueDate
    }

    private var resolvedNote: String? {
        if let parsedNote = parsedMain.note {
            return TaskTextFormatter.formattedNote(parsedNote)
        }
        return TaskTextFormatter.formattedNote(composer.note)
    }

    private var resolvedTitle: String {
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
        let lower = input.lowercased()
        if lower.range(of: #"(?:^|\s)/(?:w|r)(?=\s|$)"#, options: .regularExpression) != nil {
            return true
        }
        return Self.queueSignalPhrases.contains { lower.contains($0) }
    }

    private func parseDatePhrase(_ phrase: String) -> Date? {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return TaskParser.parse(trimmed, fallbackToRawTitle: false).dueDate
    }

    private var editingBaseTask: Task? {
        guard let editingTaskID = composer.editingTaskID else { return nil }
        return viewModel.tasks.first(where: { $0.id == editingTaskID })
    }

    private func submitComposer() {
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
            viewModel.createTask(
                rawInput: composer.rawInput,
                title: title,
                queue: resolvedQueue,
                person: person,
                dueDate: dueDate,
                note: note
            )
        }

        startNewComposer()
    }

    private func beginEditing(_ task: Task) {
        composer = TaskComposerState.edit(task: task)
        selectedMetadataField = .main
        syncMetadataEditorInputFromSelection()
        focusPrompt()
    }

    private func startNewComposer() {
        composer = TaskComposerState.capture(defaultQueue: settings.defaultQueue)
        selectedMetadataField = .main
        syncMetadataEditorInputFromSelection()
        focusPrompt()
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
        var fields: [MetadataField] = [.main, .queue, .due, .note]
        if composer.isEditing {
            fields.append(.status)
        }
        return fields
    }

    private func focusSelectedMetadataField() {
        if selectedMetadataField == .main {
            focusedComposerField = .main
        } else {
            focusedComposerField = .auxiliary
        }
    }

    private func syncMetadataEditorInputFromSelection() {
        switch selectedMetadataField {
        case .main:
            metadataEditorInput = composer.rawInput
        case .queue:
            metadataEditorInput = composer.queue == .work ? "work" : "follow up"
        case .due:
            metadataEditorInput = composer.dueText
        case .note:
            metadataEditorInput = composer.note
        case .status:
            metadataEditorInput = composer.status.rawValue
        }
    }

    private func applyMetadataEditorInput() {
        switch selectedMetadataField {
        case .main:
            composer.rawInput = metadataEditorInput
        case .queue:
            if let parsedQueue = parseQueueValue(metadataEditorInput) {
                composer.queue = parsedQueue
            }
        case .due:
            composer.dueText = metadataEditorInput
            let trimmed = metadataEditorInput.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                composer.dueDate = nil
            } else if let parsed = parseDatePhrase(trimmed) {
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
            composer.queue = composer.queue == .work ? .reachOut : .work
            metadataEditorInput = composer.queue == .work ? "work" : "follow up"
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

    private func handleEscape() {
        if composer.isEditing {
            startNewComposer()
            focusedComposerField = nil
        } else if focusedComposerField != nil {
            focusedComposerField = nil
        } else if viewModel.hasSelection {
            withAnimation(.easeOut(duration: 0.15)) {
                viewModel.clearSelection()
            }
        } else {
            focusPrompt()
        }
    }

    private func handleListArrowUp() -> Bool {
        guard focusedComposerField == nil else { return false }
        viewModel.moveSelectionUp()
        return true
    }

    private func handleListArrowDown() -> Bool {
        guard focusedComposerField == nil else { return false }
        viewModel.moveSelectionDown()
        return true
    }

    private func handleArrowLeft() -> Bool {
        guard focusedComposerField == nil else { return false }
        let tabs = TaskListViewModel.Tab.allCases
        guard let index = tabs.firstIndex(of: viewModel.selectedTab), index > 0 else { return false }
        withAnimation(.easeOut(duration: 0.15)) {
            viewModel.selectedTab = tabs[index - 1]
        }
        return true
    }

    private func handleArrowRight() -> Bool {
        guard focusedComposerField == nil else { return false }
        let tabs = TaskListViewModel.Tab.allCases
        guard let index = tabs.firstIndex(of: viewModel.selectedTab), index < tabs.count - 1 else { return false }
        withAnimation(.easeOut(duration: 0.15)) {
            viewModel.selectedTab = tabs[index + 1]
        }
        return true
    }

    private func handleListEnter() -> Bool {
        guard focusedComposerField == nil else { return false }
        guard let task = singleSelectedTask else { return false }
        beginEditing(task)
        return true
    }

    private func handleListSpace() -> Bool {
        guard focusedComposerField == nil else { return false }
        guard viewModel.hasSelection else { return false }
        for task in viewModel.selectedTasks {
            viewModel.toggleDone(task)
        }
        return true
    }

    private func handleListDelete() -> Bool {
        guard focusedComposerField == nil else { return false }
        guard viewModel.hasSelection else { return false }
        if viewModel.isMultiSelect {
            showDeleteConfirmation = true
        } else {
            viewModel.bulkDelete()
        }
        return true
    }

    private func handleSelectAll() -> Bool {
        guard focusedComposerField == nil else { return false }
        viewModel.selectAll()
        return true
    }

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

            Button("Deselect") { withAnimation { viewModel.clearSelection() } }
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
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 3)
    }

    private func parseQueueValue(_ input: String) -> TaskQueue? {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("follow") || normalized.contains("reach") || normalized == "r" {
            return .reachOut
        }
        if normalized.contains("work") || normalized == "w" {
            return .work
        }
        return nil
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
        formatter.timeStyle = .none
        return formatter
    }
}

private struct TaskComposerState {
    var editingTaskID: String?
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
        formatter.timeStyle = .none

        return TaskComposerState(
            editingTaskID: task.id,
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

private struct MainPromptKeyMonitor: NSViewRepresentable {
    var onEscape: () -> Void
    var onFocusPrompt: () -> Void
    var onTab: (_ reverse: Bool) -> Void
    var onArrowUp: () -> Bool
    var onArrowDown: () -> Bool
    var onArrowLeft: () -> Bool
    var onArrowRight: () -> Bool
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
        view.onArrowLeft = onArrowLeft
        view.onArrowRight = onArrowRight
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
        view.onArrowLeft = onArrowLeft
        view.onArrowRight = onArrowRight
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
    var onArrowLeft: (() -> Bool)?
    var onArrowRight: (() -> Bool)?
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

            // Cmd+A: select all (pass through if not handled)
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

            // Arrow Left
            if event.keyCode == 123 && modifiers.isEmpty {
                if self.onArrowLeft?() == true { return nil }
                return event
            }

            // Arrow Right
            if event.keyCode == 124 && modifiers.isEmpty {
                if self.onArrowRight?() == true { return nil }
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

            // Delete/Backspace
            if event.keyCode == 51 && modifiers.isEmpty {
                if self.onDelete?() == true { return nil }
                return event
            }

            return event
        }
    }
}
