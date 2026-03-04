import SwiftUI
import Carbon

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    let database: DatabaseManager

    @State private var confirmReset = false

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }

            quickCaptureTab
                .tabItem { Label("Quick Capture", systemImage: "keyboard") }

            notificationsTab
                .tabItem { Label("Notifications", systemImage: "bell") }

            appearanceTab
                .tabItem { Label("Appearance", systemImage: "paintpalette") }

            dataTab
                .tabItem { Label("Data", systemImage: "externaldrive") }
        }
        .padding(20)
        .frame(width: 540, height: 360)
        .alert("Reset all data?", isPresented: $confirmReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                try? database.resetAllData()
            }
        } message: {
            Text("This will permanently delete all tasks.")
        }
    }

    private var generalTab: some View {
        Form {
            Toggle("Launch at login", isOn: $settings.launchAtLogin)
            Picker("Default queue", selection: $settings.defaultQueue) {
                Text("Work").tag(TaskQueue.work)
                Text("Follow Up").tag(TaskQueue.reachOut)
            }
        }
    }

    private var quickCaptureTab: some View {
        Form {
            hotkeyEditor(
                title: "Quick Capture Hotkey",
                keyCode: $settings.quickCaptureHotKeyCode,
                modifiers: $settings.quickCaptureHotKeyModifiers,
                description: "Toggles quick capture from anywhere."
            )

            hotkeyEditor(
                title: "Open App Hotkey",
                keyCode: $settings.openAppHotKeyCode,
                modifiers: $settings.openAppHotKeyModifiers,
                description: "Brings the main app window forward."
            )

            Picker("Overlay position", selection: $settings.overlayPosition) {
                ForEach(OverlayPosition.allCases, id: \.rawValue) { pos in
                    Text(pos.displayName).tag(pos)
                }
            }
        }
    }

    private var notificationsTab: some View {
        Form {
            Toggle("Enable notifications", isOn: $settings.notificationsEnabled)
            Toggle("Morning summary", isOn: $settings.summaryEnabled)

            HStack {
                Stepper("Hour: \(settings.summaryHour)", value: $settings.summaryHour, in: 0...23)
                Stepper("Minute: \(settings.summaryMinute)", value: $settings.summaryMinute, in: 0...59)
            }

            Stepper("Default snooze: \(settings.snoozeDays) day(s)", value: $settings.snoozeDays, in: 1...30)
        }
    }

    private var appearanceTab: some View {
        Form {
            Picker("Theme", selection: $settings.appearance) {
                ForEach(AppAppearance.allCases, id: \.rawValue) { appearance in
                    Text(appearance.displayName).tag(appearance)
                }
            }
        }
    }

    private var dataTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Data")
                .font(.title3.weight(.semibold))

            Text("Reset all stored tasks and return Jot to an empty state.")
                .foregroundStyle(.secondary)

            Button("Reset all data", role: .destructive) {
                confirmReset = true
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func hotkeyEditor(
        title: String,
        keyCode: Binding<UInt32>,
        modifiers: Binding<UInt32>,
        description: String
    ) -> some View {
        Section(title) {
            Picker("Key", selection: keyCode) {
                ForEach(ShortcutFormatter.keyOptions) { option in
                    Text(option.label).tag(option.keyCode)
                }
            }

            HStack(spacing: 14) {
                modifierToggle("Control", modifiers: modifiers, flag: UInt32(controlKey))
                modifierToggle("Option", modifiers: modifiers, flag: UInt32(optionKey))
                modifierToggle("Shift", modifiers: modifiers, flag: UInt32(shiftKey))
                modifierToggle("Command", modifiers: modifiers, flag: UInt32(cmdKey))
            }

            Text("Current: \(ShortcutFormatter.displayString(keyCode: keyCode.wrappedValue, modifiers: modifiers.wrappedValue))")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(description)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func modifierToggle(_ label: String, modifiers: Binding<UInt32>, flag: UInt32) -> some View {
        Toggle(label, isOn: Binding(
            get: { modifiers.wrappedValue & flag != 0 },
            set: { enabled in
                var value = modifiers.wrappedValue
                if enabled {
                    value |= flag
                } else {
                    value &= ~flag
                }
                modifiers.wrappedValue = value
            }
        ))
        .toggleStyle(.checkbox)
    }
}
