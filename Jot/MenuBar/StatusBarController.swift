import AppKit
import Foundation

@MainActor
final class StatusBarController: NSObject {
    private var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let database: DatabaseManager
    private let settings: SettingsStore
    private let overlay: OverlayController
    private let meetingSession: MeetingSession
    private var observers: [NSObjectProtocol] = []
    private var menu: NSMenu?

    var onOpenApp: (() -> Void)?
    var onOpenDailyFocus: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?
    var onQuitCompletely: (() -> Void)?
    var canCheckForUpdates: Bool = false

    init(database: DatabaseManager, settings: SettingsStore, overlay: OverlayController, meetingSession: MeetingSession) {
        self.database = database
        self.settings = settings
        self.overlay = overlay
        self.meetingSession = meetingSession
        super.init()

        configureStatusItem()

        observers.append(
            NotificationCenter.default.addObserver(forName: .jotDatabaseDidChange, object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.rebuildMenu()
                }
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(forName: .jotSettingsDidChange, object: nil, queue: .main) { [weak self] _ in
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

    func refreshStatusItem() {
        NSStatusBar.system.removeStatusItem(statusItem)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureStatusItem()
        rebuildMenu()
    }

    @objc private func showStatusMenu() {
        rebuildMenu()
        guard let menu else { return }

        NSApp.activate(ignoringOtherApps: true)
        statusItem.popUpMenu(menu)
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
        alert.informativeText = "Enter a single meeting draft like 'Tyler' or 'Product roadmap with Tyler'."
        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")

        let draftField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        draftField.placeholderString = "Product roadmap with Tyler"
        draftField.bezelStyle = .roundedBezel
        alert.accessoryView = draftField
        alert.window.initialFirstResponder = draftField

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let draft = MeetingDraftParser.parse(draftField.stringValue)
        guard !draft.title.isEmpty else { return }

        try? meetingSession.startMeeting(title: draft.title, attendees: draft.person)
        rebuildMenu()
    }

    @objc private func endMeeting() {
        try? meetingSession.endCurrentMeeting()
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

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
        menu.addItem(makeDailyFocusMenuItem())
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ","))
        let checkForUpdatesItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
        checkForUpdatesItem.isEnabled = canCheckForUpdates
        menu.addItem(checkForUpdatesItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))

        menu.items.forEach { $0.target = self }
        self.menu = menu

        configureStatusItemButton(isInMeeting: meetingSession.isInMeeting)
    }

    private func configureStatusItem() {
        configureStatusItemButton(isInMeeting: meetingSession.isInMeeting)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(showStatusMenu)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
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
        makeConfiguredMenuItem(
            title: "Open App",
            action: #selector(openApp),
            keyCode: settings.openAppHotKeyCode,
            modifiers: settings.openAppHotKeyModifiers
        )
    }

    private func makeDailyFocusMenuItem() -> NSMenuItem {
        makeConfiguredMenuItem(
            title: "Today List",
            action: #selector(openDailyFocus),
            keyCode: settings.dailyFocusHotKeyCode,
            modifiers: settings.dailyFocusHotKeyModifiers
        )
    }

    private func makeConfiguredMenuItem(
        title: String,
        action: Selector,
        keyCode: UInt32,
        modifiers: UInt32
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: action,
            keyEquivalent: ShortcutFormatter.keyEquivalent(for: keyCode)
        )
        item.keyEquivalentModifierMask = ShortcutFormatter.modifierMask(for: modifiers)
        return item
    }

    private func configureStatusItemButton(isInMeeting: Bool) {
        guard let button = statusItem.button else { return }

        let symbolName = isInMeeting ? "record.circle.fill" : "checklist"
        let accessibilityDescription = isInMeeting ? "Jot — In Meeting" : "Jot"

        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription)
            ?? NSImage(systemSymbolName: "circle.grid.2x2.fill", accessibilityDescription: accessibilityDescription)

        if let image {
            image.isTemplate = true
            button.image = image
            button.title = ""
            button.imagePosition = .imageOnly
        } else {
            button.image = nil
            button.title = "J"
            button.font = .systemFont(ofSize: 13, weight: .semibold)
            button.imagePosition = .noImage
        }

        button.imageScaling = .scaleProportionallyDown
    }
}
