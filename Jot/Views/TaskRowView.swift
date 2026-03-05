import SwiftUI

struct TaskRowView: View {
    @Environment(\.colorScheme) private var colorScheme
    var task: Task
    var isSelected: Bool = false
    var showQueueBadge: Bool = false
    var onToggle: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: task.status == .active ? "circle" : "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(task.status == .active ? Color.secondary : Color.green)
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
                        .stroke(isSelected ? Color.accentColor.opacity(0.25) : rowStrokeColor.opacity(isHovering ? 1 : 0.7), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
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
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "due " + formatter.localizedString(for: date, relativeTo: .now)
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

    private var selectedGradientColors: [Color] {
        if colorScheme == .dark {
            return [Color.accentColor.opacity(0.10), Color.accentColor.opacity(0.05)]
        }
        return [Color.accentColor.opacity(0.08), Color.accentColor.opacity(0.04)]
    }

    private var rowStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }

    private func rowGradientColors(taskIsActive: Bool) -> [Color] {
        if colorScheme == .dark {
            return taskIsActive
                ? [Color.white.opacity(0.11), Color.white.opacity(0.05)]
                : [Color.white.opacity(0.08), Color.white.opacity(0.03)]
        }
        return taskIsActive
            ? [Color.white.opacity(0.92), Color.white.opacity(0.70)]
            : [Color.white.opacity(0.74), Color.white.opacity(0.56)]
    }
}
