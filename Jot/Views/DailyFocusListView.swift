import SwiftUI

struct DailyFocusListView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel: DailyFocusListViewModel
    var onDismiss: () -> Void

    init(database: DatabaseManager, onDismiss: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: DailyFocusListViewModel(database: database))
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 12) {
                header

                if viewModel.tasks.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.orange.opacity(0.6))
                        Text("Nothing on your list")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("Use quick capture and tap the sun icon\nto keep tasks pinned here.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 18)
                } else {
                    List {
                        ForEach(viewModel.tasks) { task in
                            DailyFocusTaskRow(
                                task: task,
                                onToggleDone: { viewModel.toggleDone(task) },
                                onRemove: { viewModel.removeFromToday(task) }
                            )
                            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .environment(\.defaultMinListRowHeight, 46)
                }

                footer
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dropDestination(for: String.self) { dropped, _ in
            var consumed = false
            for token in dropped {
                guard token.hasPrefix("jot-task:") else { continue }
                let id = String(token.dropFirst("jot-task:".count))
                guard !id.isEmpty else { continue }
                viewModel.addFromTaskID(id)
                consumed = true
            }
            return consumed
        }
        .background(DailyFocusEscapeHandler(onEscape: { onDismiss() }))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.orange)

            Text("Today")
                .font(.system(size: 15, weight: .bold))

            Spacer()
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("Drag tasks here or use the sun icon in quick capture")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
            Spacer()
            if viewModel.openCount > 0 {
                Text("\(viewModel.openCount) open")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
    }

}

private struct DailyFocusTaskRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let task: Task
    let onToggleDone: () -> Void
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    onToggleDone()
                }
            }) {
                Image(systemName: task.status == .active ? "circle" : "checkmark.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(task.status == .active ? Color.secondary : Color.green)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 14, weight: .medium))
                    .strikethrough(task.status != .active)
                    .foregroundStyle(task.status == .active ? .primary : .secondary)
                    .lineLimit(2)

                if let due = task.dueDateValue {
                    Text(TaskDueFormatter.compactLabel(for: due))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(dueColor(due).opacity(0.9))
                }
            }

            Spacer(minLength: 0)

            queueDot(task.queue)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Remove from Today list")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(rowStrokeColor, lineWidth: 1)
                )
        )
        .onHover { isHovering = $0 }
    }

    private func queueDot(_ queue: TaskQueue) -> some View {
        Circle()
            .fill(queueColor(queue))
            .frame(width: 7, height: 7)
            .help(queue.displayName)
    }

    private func queueColor(_ queue: TaskQueue) -> Color {
        switch queue {
        case .work: return .orange
        case .reachOut: return .blue
        case .thought: return .indigo
        }
    }

    private func dueColor(_ date: Date) -> Color {
        if date < Date() { return .red }
        if Calendar.current.isDateInToday(date) { return .orange }
        return .blue
    }

    private var rowStrokeColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(isHovering ? 0.14 : 0.08)
            : Color.black.opacity(isHovering ? 0.12 : 0.06)
    }
}

private struct DailyFocusEscapeHandler: NSViewRepresentable {
    var onEscape: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = DailyFocusKeyView()
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? DailyFocusKeyView)?.onEscape = onEscape
    }
}

private final class DailyFocusKeyView: NSView {
    var onEscape: (() -> Void)?
    private var monitor: Any?

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.onEscape?(); return nil }
            return event
        }
    }
}
