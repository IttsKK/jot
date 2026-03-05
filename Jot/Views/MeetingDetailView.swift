import SwiftUI

struct MeetingDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    var meeting: Meeting
    var items: [Task]
    var onToggleDone: (Task) -> Void
    var onDelete: (Task) -> Void

    private var notes: [Task] { items.filter { $0.kind == .thought } }
    private var tasks: [Task] { items.filter { $0.kind == .task && $0.queue == .work } }
    private var followUps: [Task] { items.filter { $0.kind == .task && $0.queue == .reachOut } }

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
                            Image(systemName: "person.2")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Text(meeting.attendeeList.joined(separator: ", "))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 4)

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

    private func meetingItemRow(_ item: Task) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if item.kind == .task {
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
                    .strikethrough(item.status != .active && item.kind == .task)
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
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return Text("due " + formatter.localizedString(for: date, relativeTo: .now))
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.14)))
            .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 1))
            .foregroundStyle(color.opacity(0.9))
    }

    private var rowStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }
}
