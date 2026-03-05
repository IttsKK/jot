import SwiftUI

struct CaptureView: View {
    @ObservedObject var viewModel: CaptureViewModel
    var onDismiss: () -> Void

    @FocusState private var focused: Bool

    private var isInMeeting: Bool { viewModel.meetingSession.isInMeeting }
    private var meetingTitle: String { viewModel.meetingSession.activeMeeting?.title ?? "" }
    private var isThought: Bool { viewModel.parsed.queue == .thought }
    private var hasForcedMode: Bool { viewModel.forcedQueue != nil }

    var body: some View {
        ZStack {
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

                chipRow
                    .animation(.easeOut(duration: 0.16), value: viewModel.parsed)
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            viewModel.updateParse()
            requestFocusSoon()
        }
        .onChange(of: viewModel.focusNonce) { _, _ in
            requestFocusSoon()
        }
        .background(EscapeKeyHandler(onEscape: {
            viewModel.clear()
            onDismiss()
        }))
    }

    private var capturePrompt: String {
        if isInMeeting { return "Note, task, follow-up..." }
        if viewModel.forcedQueue == .thought { return "What's on your mind?" }
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
            if isThought {
                modeChip("Thought", color: .indigo, isForced: viewModel.forcedQueue == .thought)
            } else {
                modeChip("Queue: \(viewModel.parsed.queue.displayName)",
                         color: queueColor(viewModel.parsed.queue),
                         isForced: viewModel.forcedQueue != nil)
                if let date = viewModel.parsed.dueDate {
                    chip(relativeDate(date), color: .pink)
                }
                if let note = viewModel.parsed.note, !note.isEmpty {
                    chip("Note", color: .teal).help(note)
                }
            }

            if viewModel.input.isEmpty && !hasForcedMode {
                Spacer()
                Text("// thought  /w work  /r follow-up")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
        }
    }

    /// Chip that visually indicates when the value was locked in by a mode prefix
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

    private func queueColor(_ queue: TaskQueue) -> Color {
        switch queue {
        case .work: return .orange
        case .reachOut: return .blue
        case .thought: return .indigo
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    private func requestFocusSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            focused = true
        }
    }
}

private struct EscapeKeyHandler: NSViewRepresentable {
    var onEscape: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyHandlerView()
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? KeyHandlerView)?.onEscape = onEscape
    }
}

private final class KeyHandlerView: NSView {
    var onEscape: (() -> Void)?
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
            return event
        }
    }
}
