import SwiftUI
import Carbon

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    let database: DatabaseManager

    @State private var confirmReset = false

    var body: some View {
        TabView {
            settingsPage {
                settingsSection("General", description: "Core app behavior and defaults.") {
                    settingRow("Launch at login", detail: "Start Jot automatically when you sign in.") {
                        Toggle("", isOn: $settings.launchAtLogin)
                            .labelsHidden()
                    }

                    settingRow("Default queue", detail: "Used for quick capture when no queue is specified.") {
                        Picker("Default queue", selection: $settings.defaultQueue) {
                            Text("Work").tag(TaskQueue.work)
                            Text("Follow Up").tag(TaskQueue.reachOut)
                        }
                        .labelsHidden()
                        .frame(width: 180)
                    }
                }
            }
            .tabItem { Label("General", systemImage: "gear") }

            settingsPage {
                settingsSection("Hotkeys", description: "Global shortcuts for capture and window management.") {
                    hotkeyEditor(
                        title: "Quick Capture",
                        keyCode: $settings.quickCaptureHotKeyCode,
                        modifiers: $settings.quickCaptureHotKeyModifiers,
                        description: "Toggles quick capture from anywhere."
                    )

                    hotkeyEditor(
                        title: "Open App",
                        keyCode: $settings.openAppHotKeyCode,
                        modifiers: $settings.openAppHotKeyModifiers,
                        description: "Brings the main app window forward."
                    )

                    hotkeyEditor(
                        title: "Today List",
                        keyCode: $settings.dailyFocusHotKeyCode,
                        modifiers: $settings.dailyFocusHotKeyModifiers,
                        description: "Opens the Today list window."
                    )
                }

                settingsSection("Overlay", description: "Controls where the quick capture panel appears.") {
                    settingRow("Panel position", detail: "Choose whether capture opens centered or higher on screen.") {
                        Picker("Overlay position", selection: $settings.overlayPosition) {
                            ForEach(OverlayPosition.allCases, id: \.rawValue) { pos in
                                Text(pos.displayName).tag(pos)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                    }

                    settingRow("Show command previews", detail: "Preview slash commands automatically in quick capture. If off, press Tab to reveal them.") {
                        Toggle("", isOn: $settings.quickCaptureCommandPreviewEnabled)
                            .labelsHidden()
                    }
                }
            }
            .tabItem { Label("Quick Capture", systemImage: "keyboard") }

            settingsPage {
                settingsSection("Notifications", description: "Reminder and summary behavior.") {
                    settingRow("Enable notifications", detail: "Allow Jot to send reminders for due items.") {
                        Toggle("", isOn: $settings.notificationsEnabled)
                            .labelsHidden()
                    }

                    settingRow("Morning summary", detail: "Send a daily summary at the configured time.") {
                        Toggle("", isOn: $settings.summaryEnabled)
                            .labelsHidden()
                    }

                    settingRow("Summary hour", detail: "24-hour time.") {
                        Stepper(value: $settings.summaryHour, in: 0...23) {
                            Text("\(settings.summaryHour)")
                                .monospacedDigit()
                        }
                        .frame(width: 120)
                    }

                    settingRow("Summary minute", detail: "Minute of the hour.") {
                        Stepper(value: $settings.summaryMinute, in: 0...59) {
                            Text(String(format: "%02d", settings.summaryMinute))
                                .monospacedDigit()
                        }
                        .frame(width: 120)
                    }

                    settingRow("Default snooze", detail: "How long reminder snoozes last.") {
                        Stepper(value: $settings.snoozeDays, in: 1...30) {
                            Text("\(settings.snoozeDays) day\(settings.snoozeDays == 1 ? "" : "s")")
                                .monospacedDigit()
                        }
                        .frame(width: 140)
                    }
                }
            }
            .tabItem { Label("Notifications", systemImage: "bell") }

            settingsPage {
                settingsSection("Appearance", description: "Theme and presentation.") {
                    settingRow("Theme", detail: "Match the system or force a specific appearance.") {
                        Picker("Theme", selection: $settings.appearance) {
                            ForEach(AppAppearance.allCases, id: \.rawValue) { appearance in
                                Text(appearance.displayName).tag(appearance)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                    }
                }
            }
            .tabItem { Label("Appearance", systemImage: "paintpalette") }

            settingsPage {
                settingsSection("Data", description: "Danger zone for local app state.") {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Reset all data")
                                .font(.headline)
                            Text("Permanently delete all tasks, meetings, and Today list items.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Reset all data", role: .destructive) {
                            confirmReset = true
                        }
                    }
                }
            }
            .tabItem { Label("Data", systemImage: "externaldrive") }
        }
        .frame(width: 700, height: 480)
        .alert("Reset all data?", isPresented: $confirmReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                try? database.resetAllData()
            }
        } message: {
            Text("This will permanently delete all tasks.")
        }
    }

    private func settingsPage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func settingsSection<Content: View>(
        _ title: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private func settingRow<Control: View>(
        _ title: String,
        detail: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 20)
            control()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func hotkeyEditor(
        title: String,
        keyCode: Binding<UInt32>,
        modifiers: Binding<UInt32>,
        description: String
    ) -> some View {
        HotkeyRecorderRow(
            title: title,
            keyCode: keyCode,
            modifiers: modifiers,
            description: description
        )
    }
}

private struct HotkeyRecorderRow: View {
    let title: String
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32
    let description: String

    @State private var isRecording = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 20)
                ShortcutRecorderField(
                    keyCode: $keyCode,
                    modifiers: $modifiers,
                    isRecording: $isRecording
                )
                .frame(width: 220, height: 34)
            }

            Text(isRecording ? "Press the shortcut now. Esc cancels." : "Click the field, then press a shortcut with at least one modifier.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct ShortcutRecorderField: NSViewRepresentable {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32
    @Binding var isRecording: Bool

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.onShortcutCaptured = { newKeyCode, newModifiers in
            keyCode = newKeyCode
            modifiers = newModifiers
        }
        view.onRecordingChanged = { recording in
            isRecording = recording
        }
        view.keyCode = keyCode
        view.modifiers = modifiers
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        nsView.onShortcutCaptured = { newKeyCode, newModifiers in
            keyCode = newKeyCode
            modifiers = newModifiers
        }
        nsView.onRecordingChanged = { recording in
            isRecording = recording
        }
        nsView.keyCode = keyCode
        nsView.modifiers = modifiers
    }
}

private final class ShortcutRecorderNSView: NSView {
    var keyCode: UInt32 = 0 {
        didSet { updateDisplay() }
    }

    var modifiers: UInt32 = 0 {
        didSet { updateDisplay() }
    }

    var onShortcutCaptured: ((UInt32, UInt32) -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?

    private let label = NSTextField(labelWithString: "")
    private var pendingModifiers: UInt32 = 0
    private var isRecording = false {
        didSet {
            guard oldValue != isRecording else { return }
            onRecordingChanged?(isRecording)
            updateDisplay()
            updateAppearance()
        }
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            pendingModifiers = 0
            isRecording = true
        }
        return became
    }

    override func resignFirstResponder() -> Bool {
        pendingModifiers = 0
        isRecording = false
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 53 {
            window?.makeFirstResponder(nil)
            return
        }

        let newKeyCode = UInt32(event.keyCode)
        let newModifiers = ShortcutFormatter.carbonModifiers(from: event.modifierFlags)

        guard !ShortcutFormatter.isModifierOnlyKey(newKeyCode) else {
            return
        }

        guard newModifiers != 0 else {
            NSSound.beep()
            return
        }

        onShortcutCaptured?(newKeyCode, newModifiers)
        window?.makeFirstResponder(nil)
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }
        pendingModifiers = ShortcutFormatter.carbonModifiers(from: event.modifierFlags)
        updateDisplay()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func setup() {
        wantsLayer = true

        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateDisplay()
        updateAppearance()
    }

    private func updateDisplay() {
        if isRecording {
            let modifiersText = ShortcutFormatter.modifierDisplayString(modifiers: pendingModifiers)
            label.stringValue = modifiersText.isEmpty ? "Type shortcut" : modifiersText
        } else {
            label.stringValue = ShortcutFormatter.displayString(keyCode: keyCode, modifiers: modifiers)
        }
    }

    private func updateAppearance() {
        guard let layer else { return }

        layer.cornerRadius = 8
        layer.borderWidth = 1

        if isRecording {
            layer.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
            layer.borderColor = NSColor.controlAccentColor.cgColor
            label.textColor = .labelColor
        } else {
            layer.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer.borderColor = NSColor.separatorColor.cgColor
            label.textColor = .secondaryLabelColor
        }
    }
}
