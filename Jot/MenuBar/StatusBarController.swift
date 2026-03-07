import AppKit
import Foundation

@MainActor
final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let database: DatabaseManager
    private let settings: SettingsStore
    private let overlay: OverlayController
    private let meetingSession: MeetingSession
    private var observers: [NSObjectProtocol] = []

    var onOpenApp: (() -> Void)?
    var onOpenDailyFocus: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?
    var canCheckForUpdates: Bool = false

    init(database: DatabaseManager, settings: SettingsStore, overlay: OverlayController, meetingSession: MeetingSession) {
        self.database = database
        self.settings = settings
        self.overlay = overlay
        self.meetingSession = meetingSession
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Jot")
            button.imagePosition = .imageOnly
        }

        statusItem.menu = NSMenu()
        statusItem.menu?.delegate = self

        observers.append(
            NotificationCenter.default.addObserver(forName: .jotDatabaseDidChange, object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.rebuildMenu()
                }
            }
        )

        rebuildMenu()
    }

    deinit {
        for token in observers {
            NotificationCenter.default.removeObserver(token)
        }
    }

    @objc private func quickAdd() {
        overlay.show()
    }

    @objc private func openApp() {
        onOpenApp?()
    }

    @objc private func openDailyFocus() {
        onOpenDailyFocus?()
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func checkForUpdates() {
        onCheckForUpdates?()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func startMeeting() {
        let alert = NSAlert()
        alert.messageText = "Start Meeting"
        alert.informativeText = "Enter a meeting title and who it's with (optional)."
        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")

        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 300, height: 56))
        stack.orientation = .vertical
        stack.spacing = 8

        let titleField = NSTextField(frame: NSRect(x: 0, y: 28, width: 300, height: 24))
        titleField.placeholderString = "Meeting title"
        titleField.bezelStyle = .roundedBezel

        let attendeesField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        attendeesField.placeholderString = "With (optional)"
        attendeesField.bezelStyle = .roundedBezel

        stack.addArrangedSubview(titleField)
        stack.addArrangedSubview(attendeesField)
        alert.accessoryView = stack
        alert.window.initialFirstResponder = titleField

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let attendees = attendeesField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        try? meetingSession.startMeeting(title: title, attendees: attendees.isEmpty ? nil : attendees)
        rebuildMenu()
    }

    @objc private func endMeeting() {
        try? meetingSession.endCurrentMeeting()
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        // Meeting section
        if meetingSession.isInMeeting, let meeting = meetingSession.activeMeeting {
            let meetingItem = NSMenuItem(title: "In Meeting: \(meeting.title)", action: nil, keyEquivalent: "")
            meetingItem.isEnabled = false
            menu.addItem(meetingItem)

            let endItem = NSMenuItem(title: "End Meeting", action: #selector(endMeeting), keyEquivalent: "")
            menu.addItem(endItem)
            menu.addItem(.separator())
        } else {
            let startItem = NSMenuItem(title: "Start Meeting", action: #selector(startMeeting), keyEquivalent: "")
            menu.addItem(startItem)
            menu.addItem(.separator())
        }

        let dueTodayCount = (try? database.dueTodayCount()) ?? 0
        let summary = NSMenuItem(title: "Due today: \(dueTodayCount)", action: nil, keyEquivalent: "")
        summary.isEnabled = false
        menu.addItem(summary)

        let dueTasks = (try? database.dueTodayTasks(limit: 5)) ?? []
        if dueTasks.isEmpty {
            let none = NSMenuItem(title: "No due tasks", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        } else {
            for task in dueTasks {
                let item = NSMenuItem(title: task.title, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(makeQuickAddMenuItem())
        menu.addItem(makeOpenAppMenuItem())
        menu.addItem(NSMenuItem(title: "Open Today Focus List", action: #selector(openDailyFocus), keyEquivalent: "d"))
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ","))
        let checkForUpdatesItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
        checkForUpdatesItem.isEnabled = canCheckForUpdates
        menu.addItem(checkForUpdatesItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))

        menu.items.forEach { $0.target = self }
        statusItem.menu = menu

        if let button = statusItem.button {
            if meetingSession.isInMeeting {
                button.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Jot — In Meeting")
            } else {
                button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Jot")
            }
        }
    }

    private func makeQuickAddMenuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "Quick Capture",
            action: #selector(quickAdd),
            keyEquivalent: ShortcutFormatter.keyEquivalent(for: settings.quickCaptureHotKeyCode)
        )
        item.keyEquivalentModifierMask = ShortcutFormatter.modifierMask(for: settings.quickCaptureHotKeyModifiers)
        return item
    }

    private func makeOpenAppMenuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "Open App",
            action: #selector(openApp),
            keyEquivalent: ShortcutFormatter.keyEquivalent(for: settings.openAppHotKeyCode)
        )
        item.keyEquivalentModifierMask = ShortcutFormatter.modifierMask(for: settings.openAppHotKeyModifiers)
        return item
    }
}

extension StatusBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }
}
