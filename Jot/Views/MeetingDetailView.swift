import SwiftUI

struct MeetingDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    var meeting: Meeting
    var items: [Task]
    var onUpdateSummary: (String?) -> Void
    var onToggleDone: (Task) -> Void
    var onDelete: (Task) -> Void

    @State private var summaryDraft: String = ""

    private var notes: [Task] { items.filter { $0.queue == .thought } }
    private var tasks: [Task] { items.filter { $0.queue == .work } }
    private var followUps: [Task] { items.filter { $0.queue == .reachOut } }

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text(meeting.title)
                        .font(.system(size: 22, weight: .bold))

                    HStack(spacing: 12) {
                        if let start = meeting.startedAtValue {
                            Label(dateFormatter.string(from: start), systemImage: "calendar")
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

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Summary", systemImage: "text.bubble")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Save Summary") {
                            let trimmed = summaryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            onUpdateSummary(trimmed.isEmpty ? nil : TaskTextFormatter.formattedNote(trimmed))
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    }

                    TextEditor(text: $summaryDraft)
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
                        sectionHeader("Notes", icon: "note.text", color: .indigo)
                        ForEach(notes) { item in
                            meetingItemRow(item)
                        }
                    }

                    if !tasks.isEmpty {
                        sectionHeader("Tasks", icon: "checkmark.square", color: .orange)
                        ForEach(tasks) { item in
                            meetingItemRow(item)
                        }
                    }

                    if !followUps.isEmpty {
                        sectionHeader("Follow Ups", icon: "arrow.turn.up.right", color: .blue)
                        ForEach(followUps) { item in
                            meetingItemRow(item)
                        }
                    }
                }
            }
            .padding(16)
        }
        .onAppear {
            summaryDraft = meeting.summary ?? ""
        }
        .onChange(of: meeting.summary) { _, newValue in
            summaryDraft = newValue ?? ""
        }
    }

    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 4)
    }

    private var panelStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }

    private func meetingItemRow(_ item: Task) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if item.queue != .thought {
                Button(action: { onToggleDone(item) }) {
                    Image(systemName: item.status == .active ? "circle" : "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(item.status == .active ? Color.secondary : Color.green)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "text.quote")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.indigo.opacity(0.7))
                    .frame(width: 18)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 14, weight: .medium))
                    .strikethrough(item.status != .active && item.queue != .thought)
                    .foregroundStyle(item.status != .active ? .secondary : .primary)

                if let note = item.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    if let person = item.person, !person.isEmpty {
                        personPill(person)
                    }
                    if let due = item.dueDateValue {
                        duePill(due)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(rowStrokeColor, lineWidth: 1)
                )
        )
        .contextMenu {
            Button(role: .destructive) { onDelete(item) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .draggable("jot-task:\(item.id)")
    }

    private func personPill(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.blue.opacity(0.14)))
            .overlay(Capsule().stroke(Color.blue.opacity(0.25), lineWidth: 1))
            .foregroundStyle(Color.blue.opacity(0.9))
    }

    private func duePill(_ date: Date) -> some View {
        let color: Color = date < Date() ? .red : Calendar.current.isDateInToday(date) ? .orange : .blue
        return Text("due " + dueLabel(date))
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.14)))
            .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 1))
            .foregroundStyle(color.opacity(0.9))
    }

    private func dueLabel(_ date: Date) -> String {
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
            dayText = weekdayFormatter.string(from: date)
        default:
            dayText = dateOnlyFormatter.string(from: date)
        }

        if hasExplicitDueTime(date) {
            return "\(dayText) \(timeOnlyFormatter.string(from: date))"
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

    private var dateOnlyFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }

    private var weekdayFormatter: DateFormatter {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE")
        return f
    }

    private var timeOnlyFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }

    private var rowStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }
}
