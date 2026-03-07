import SwiftUI

struct TaskRowView: View {
    @Environment(\.colorScheme) private var colorScheme
    var task: Task
    var isSelected: Bool = false
    var showQueueBadge: Bool = false
    var onToggle: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    onToggle()
                }
            }) {
                Image(systemName: task.status == .active ? "circle" : "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(task.status == .active ? Color.secondary.opacity(0.7) : Color.green)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.system(size: 15, weight: .semibold))
                    .strikethrough(task.status != .active)
                    .foregroundStyle(task.status == .active ? .primary : .secondary)
                    .lineLimit(2)

                if let note = task.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    if task.isInDailyFocus {
                        todayPill
                    }
                    if let due = task.dueDateValue {
                        pill(text: relativeDueText(due), color: dueColor(due))
                    }
                    if showQueueBadge {
                        pill(text: task.queue.displayName, color: queueColor(task.queue))
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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
                                    colors: rowGradientColors(taskIsActive: task.status == .active),
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
        .draggable("jot-task:\(task.id)")
    }

    private var todayPill: some View {
        HStack(spacing: 3) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 9, weight: .bold))
            Text("today")
                .font(.system(size: 11, weight: .bold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.orange.opacity(0.16)))
        .overlay(Capsule().stroke(Color.orange.opacity(0.28), lineWidth: 1))
        .foregroundStyle(Color.orange.opacity(0.95))
    }

    private func queueColor(_ queue: TaskQueue) -> Color {
        switch queue {
        case .work: return .orange
        case .reachOut: return .blue
        case .thought: return .indigo
        }
    }

    private func pill(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(color.opacity(0.16))
            )
            .overlay(
                Capsule().stroke(color.opacity(0.28), lineWidth: 1)
            )
            .foregroundStyle(color.opacity(0.95))
    }

    private func relativeDueText(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
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
            return "due \(dayText) \(shortTimeFormatter.string(from: date))"
        }
        return "due \(dayText)"
    }

    private func dueColor(_ date: Date) -> Color {
        if date < Date() {
            return .red
        }
        if Calendar.current.isDateInToday(date) {
            return .orange
        }
        return .blue
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

    private func rowGradientColors(taskIsActive: Bool) -> [Color] {
        if colorScheme == .dark {
            return taskIsActive
                ? [Color.white.opacity(isHovering ? 0.13 : 0.11), Color.white.opacity(isHovering ? 0.07 : 0.05)]
                : [Color.white.opacity(isHovering ? 0.10 : 0.08), Color.white.opacity(isHovering ? 0.05 : 0.03)]
        }
        return taskIsActive
            ? [Color.white.opacity(isHovering ? 0.98 : 0.92), Color.white.opacity(isHovering ? 0.82 : 0.70)]
            : [Color.white.opacity(isHovering ? 0.82 : 0.74), Color.white.opacity(isHovering ? 0.64 : 0.56)]
    }
}
