import AppKit
import Foundation

@MainActor
final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let database: DatabaseManager
    private let settings: SettingsStore
    private let overlay: OverlayController
    private var observers: [NSObjectProtocol] = []

    var onOpenApp: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?
    var canCheckForUpdates: Bool = false

    init(database: DatabaseManager, settings: SettingsStore, overlay: OverlayController) {
        self.database = database
        self.settings = settings
        self.overlay = overlay
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

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func checkForUpdates() {
        onCheckForUpdates?()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func rebuildMenu() {
        let menu = NSMenu()

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
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ","))
        let checkForUpdatesItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
        checkForUpdatesItem.isEnabled = canCheckForUpdates
        menu.addItem(checkForUpdatesItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))

        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
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
